class AutomationRuleListener < BaseListener # rubocop:disable Metrics/ClassLength
  # Palavras de opt-out (descadastro) do WhatsApp marketing. Casamento por IGUALDADE (não
  # "contains") sobre a mensagem normalizada — acento/caixa/pontuação-insensível, ver
  # #opt_out_message? — pra "PARAR"/"Sair"/"stop."/"CANCELAR" descadastrarem, mas "não vou
  # parar de comprar" (que só CONTÉM "parar") NÃO. Lista central e extensível.
  OPT_OUT_KEYWORDS = %w[parar sair stop cancelar].freeze

  # Direções válidas do filtro de gatilho (trigger_config['direction']). 'both' é o default e
  # NÃO filtra nada (comportamento histórico). Resolve o bug clássico: uma regra "ao criar
  # conversa → atribuir ao time X" que também disparava quando o AGENTE inicia a conversa
  # (saída/outbound), jogando-a no time errado. Ver #flow_trigger_direction e TriggerConfig.vue.
  FLOW_TRIGGER_DIRECTIONS = %w[inbound outbound both].freeze

  # Teto do scan que procura quem INICIOU o ciclo atual (ver #first_message_of_reopened_cycle). A
  # iniciativa humana, quando existe, está nas PRIMEIRAS mensagens do ciclo — o sistema fala uma ou
  # três vezes (pergunta do NPS, agradecimento, boas-vindas do flow) e então alguém de verdade
  # aparece. O teto evita carregar um ciclo inteiro (que pode ter centenas de mensagens) só para
  # achá-la. Estourar o teto sem achar humano cai no fallback (comportamento de hoje), não em
  # 'outbound' — o pior que acontece é o filtro não barrar, nunca o cliente ficar sem resposta.
  CYCLE_SCAN_LIMIT = 20

  def conversation_updated(event)
    process_conversation_event(event, 'conversation_updated')
  end

  # Um agente humano ASSUMIR a conversa ja encerra o menu do bot - nao da pra esperar ele digitar. O
  # cancelamento por MENSAGEM deixava aberta a janela entre "assumi" e "mandei a primeira mensagem":
  # a resposta do cliente nesse meio era capturada pelo wait_for_reply velho e virava "Nao entendi".
  def assignee_changed(event)
    cancel_pending_flow_waits_on_assignment(event)
  end

  def conversation_created(event)
    process_conversation_event(event, 'conversation_created')
  end

  def conversation_opened(event)
    process_conversation_event(event, 'conversation_opened')
  end

  def conversation_resolved(event)
    process_conversation_event(event, 'conversation_resolved')
  end

  def message_created(event)
    message = event.data[:message]

    return if ignore_message_created_event?(event)

    account = message.try(:account)
    cancel_pending_flow_waits_on_agent_reply(account, message)
    payload = { message: message, changed_attributes: event.data[:changed_attributes] }

    run_engine('message_created', account, message.conversation, payload)
  end

  private

  def process_conversation_event(event, event_name)
    return if performed_by_automation?(event)

    auto_reply_skip_events = %w[conversation_created conversation_opened]
    return if auto_reply_skip_events.include?(event_name) && ignore_auto_reply_event?(event)

    conversation = event.data[:conversation]
    account = conversation.account
    payload = { changed_attributes: event.data[:changed_attributes] }

    run_engine(event_name, account, conversation, payload)
  end

  # Motor unificado, gated por conta: com a flag `flows` ligada, a conta roda os Flows (que
  # o backfill criou espelhando as regras antigas); sem ela, roda as AutomationRules como
  # sempre. Mutuamente exclusivo por conta — é a mitigação de R-1 (dupla-execução) durante a
  # coexistência, sem tocar dados e reversível (desligar a flag volta ao motor antigo).
  def run_engine(event_name, account, conversation, payload)
    return if account.blank?

    if flows_engine_active?(account)
      run_flows(event_name, account, conversation, payload)
    else
      run_rules(event_name, account, conversation, payload)
    end
  end

  # O motor Flow só assume quando a flag está ligada E a conta já tem flows (o backfill
  # rodou). Sem o segundo gate, ligar a flag antes do backfill silenciaria TODAS as
  # automations da conta (run_flows iteraria vazio e as AutomationRules nunca rodariam).
  def flows_engine_active?(account)
    return false unless account.flows_engine_enabled?

    Rails.cache.fetch("flows_present:#{account.id}", expires_in: 2.minutes) do
      account.flows.active.exists?
    end
  end

  def run_rules(event_name, account, conversation, payload)
    current_account_rules(event_name, account).each do |rule|
      conditions_match = ::AutomationRules::ConditionsFilterService.new(rule, conversation, payload).perform
      ::AutomationRules::ActionService.new(rule, account, conversation).perform if conditions_match.present?
    end
  end

  def run_flows(event_name, account, conversation, payload)
    # Uma mensagem incoming pode ser CONSUMIDA antes de qualquer disparo — opt-out de compliance
    # ("PARAR") OU retomada de um wait_for_reply pendente (F2) — e então run_flows aborta, sem
    # disparar flow novo (por-evento/keyword) com a mesma mensagem. Só corre em message_created
    # (único evento com a mensagem no payload) e só com o motor Flow ativo (estamos em run_flows).
    return if event_name == 'message_created' && incoming_message_consumed?(account, conversation, payload)

    # Direção do evento (inbound/outbound) resolvida SOB DEMANDA e memoizada: só é calculada
    # quando algum flow filtra por direção — o caso comum ('both'/ausente) nunca a materializa,
    # então não há query extra na não-regressão. Proc LOCAL de propósito (o listener é singleton:
    # uma ivar vazaria estado entre threads/eventos). Ver #memoized_event_direction.
    event_direction = memoized_event_direction(event_name, conversation, payload)

    current_account_flows(event_name, account).each do |flow|
      next unless flow_direction_matches?(flow, event_direction)

      gate = ::Flows::RuleAdapter.new(conditions: flow.trigger_config['conditions'], flow: flow)
      conditions_match = ::AutomationRules::ConditionsFilterService.new(gate, conversation, payload).perform
      ::Flows::RunnerService.new(flow: flow, conversation: conversation, trigger_payload: payload).perform if conditions_match.present?
    end

    # Os Flows `trigger_type: keyword` casam contra o CONTEÚDO da mensagem, não contra um
    # event_name — por isso ficam fora do laço por-evento e só rodam em message_created (o
    # único evento que carrega a mensagem no payload). A gate `flows_engine_active?` já foi
    # aplicada por run_engine, então reaproveitamos o cache de flows sem re-checá-la.
    run_keyword_flows(account, conversation, payload, event_direction) if event_name == 'message_created'
  end

  # Gatilho `keyword`: dispara os Flows keyword-triggered ativos quando o conteúdo de uma
  # mensagem INCOMING de contato casa com as palavras-chave em trigger_config. Anti-loop já
  # garantido por ignore_message_created_event? (mensagens com flow_id nem chegam ao listener)
  # e reforçado aqui pelo filtro incoming (as mensagens que o motor gera são outgoing).
  def run_keyword_flows(account, conversation, payload, event_direction)
    message = payload[:message]
    return unless message&.incoming? && !message.private?

    content = message.content.to_s
    return if content.blank?

    current_account_keyword_flows(account).each do |flow|
      next unless keyword_flow_fires?(flow, content, event_direction)

      ::Flows::RunnerService.new(flow: flow, conversation: conversation, trigger_payload: payload).perform
    end
  end

  # Um keyword flow dispara quando o conteúdo casa E a direção casa. Gatilho keyword é inbound por
  # natureza (só corre em mensagem incoming): honramos o filtro literalmente — 'outbound' nunca
  # casa (correto), 'inbound'/'both' casam. Extraído para manter #run_keyword_flows simples.
  def keyword_flow_fires?(flow, content, event_direction)
    keyword_trigger_match?(content, flow.trigger_config) && flow_direction_matches?(flow, event_direction)
  end

  # Resolve a direção do evento apenas quando LIDA (memoizada no fechamento do lambda). Para
  # message_created a direção é a da PRÓPRIA mensagem (payload — sem I/O); para eventos de conversa
  # é a da 1ª mensagem não-activity do CICLO ATUAL (uma query indexada). Devolve sempre 'inbound' ou
  # 'outbound', então o `memo ||=` memoiza corretamente (nunca nil/false).
  def memoized_event_direction(event_name, conversation, payload)
    memo = nil
    lambda do
      memo ||= if event_name == 'message_created'
                 message_direction(payload[:message])
               else
                 conversation_direction(conversation, event_name)
               end
    end
  end

  # Um flow passa no filtro de direção quando é 'both' (default — sem filtro) ou quando a direção
  # configurada é EXATAMENTE a do evento. Só invoca o resolvedor (e sua eventual query) para os
  # flows que de fato filtram; o caso 'both' devolve antes de tocá-lo.
  def flow_direction_matches?(flow, event_direction)
    wanted = flow_trigger_direction(flow)
    wanted == 'both' || wanted == event_direction.call
  end

  # Direção configurada do gatilho: 'inbound' | 'outbound' | 'both' (default). Fonte PRIMÁRIA é
  # trigger_config['direction'] (a projeção que o canvas grava). Como o canvas TAMBÉM persiste a
  # direção no próprio nó `trigger` da definition (updateSelectedNode espalha o patch no nó), lemos
  # de lá como FALLBACK — assim o filtro já funciona ponta-a-ponta antes mesmo de a projeção do
  # FlowCanvasView copiar `direction` para trigger_config (ver TODO no canvas). Valor ausente/
  # desconhecido → 'both' (sem filtro; preserva o comportamento atual / não-regressão).
  def flow_trigger_direction(flow)
    config = flow.trigger_config
    raw = config['direction'] if config.is_a?(Hash)
    raw = trigger_node_direction(flow) if raw.blank?
    FLOW_TRIGGER_DIRECTIONS.include?(raw.to_s) ? raw.to_s : 'both'
  end

  # Fallback: a direção gravada no nó `trigger` da definition (usada quando trigger_config ainda
  # não a projeta). nil se não houver nó de gatilho — aí #flow_trigger_direction cai em 'both'.
  def trigger_node_direction(flow)
    node = flow.nodes.find { |n| n.is_a?(Hash) && n['type'] == 'trigger' }
    node && node['direction']
  end

  # Direção da CONVERSA no instante do evento: a da 1ª mensagem não-activity do CICLO ATUAL — não
  # a da 1ª mensagem da história. "Ciclo atual" = o que começa na ÚLTIMA resolução (ou na criação
  # da conversa, se ela nunca foi resolvida). É a única leitura que responde a pergunta que o
  # usuário faz ao marcar "Entrada (contato inicia)": quem iniciou ESTE atendimento?
  #
  # Sem o recorte por ciclo a direção fica COLADA na origem histórica e o filtro vira ruído numa
  # conversa reaberta (bug real, AGN conv 110: nascida incoming há 9 dias, a AGENTE reabre com um
  # template e o contato só responde → o flow 'inbound' disparava). Pior ainda com
  # `lock_to_single_conversation`, em que a conversa é eternamente reaproveitada e a 1ª mensagem
  # NUNCA representa o ciclo corrente — o cenário da AGN.
  #
  # É ROBUSTO porque o AutomationRuleListener roda ASSÍNCRONO (EventDispatcherJob.perform_later):
  # quando o job corre, a conversa e as mensagens do ciclo já commitaram. No caso outbound (agente
  # inicia a conversa), o controller cria conversa + 1ª mensagem OUTGOING na MESMA transação, logo
  # o after_create_commit só dispara com a outgoing já presente. Usamos all_messages (não
  # `messages`) para ignorar o isolamento por time: a direção é quem INICIOU o ciclo, não o que o
  # time atual enxerga. Sem mensagem direcional → 'inbound' (fail-open ao comportamento de hoje;
  # uma conversa sem mensagem não é o outbound-iniciado-por-agente, que sempre carrega a outgoing).
  def conversation_direction(conversation, event_name)
    scope = conversation.all_messages.where.not(message_type: :activity).reorder(:created_at, :id)
    first = first_message_of_reopened_cycle(conversation, scope) if event_name == 'conversation_opened'
    first ||= scope.first
    first.nil? || first.incoming? ? 'inbound' : 'outbound'
  end

  # Recorta o ciclo SÓ em conversation_opened, o único evento de conversa cujo gatilho é, por
  # construção, o início de um ciclo novo — e onde a mensagem que reabriu garante que o ciclo não
  # é vazio. Os demais ficam de fora de propósito:
  #   • conversation_created → a conversa acabou de nascer, jamais foi resolvida: o ciclo atual JÁ
  #     começa na criação e a leitura é idêntica à de hoje. Pular é otimização (poupa a query do
  #     boundary), não exceção semântica — e é o caso que hoje funciona e não pode regredir.
  #   • conversation_updated/_resolved → podem ocorrer com o ciclo ainda VAZIO (ex.: trocar o time
  #     de uma conversa já resolvida). Recortar ali exigiria uma regra de desempate para "ciclo sem
  #     mensagem" e viraria regressão (a conversa outbound-iniciada passaria a ler 'inbound').
  # nil quando não há resolução registrada, quando nada foi dito depois dela OU quando ninguém de
  # carne e osso falou no ciclo — aí #conversation_direction cai na 1ª mensagem da conversa
  # (comportamento de hoje). Nunca inventamos 'outbound' a partir de um ciclo só de sistema.
  def first_message_of_reopened_cycle(conversation, scope)
    boundary = last_resolved_at(conversation)
    return nil if boundary.nil?

    scope.where(created_at: boundary..).limit(CYCLE_SCAN_LIMIT).detect { |message| human_initiated?(message) }
  end

  # Quem INICIA um ciclo é gente: o contato (incoming) ou um humano de verdade (outgoing que o motor
  # não gerou). Mensagem de SISTEMA não inicia ciclo — logo depois de uma resolução quem fala
  # primeiro é quase sempre ele (a pergunta do NPS, as boas-vindas de um flow), e como tudo isso é
  # outgoing, contá-las faria TODO ciclo nascer 'outbound'. O estrago seria pior que o bug original:
  # o cliente que voltasse espontaneamente ("Bom dia", 3 dias depois do NPS) ficaria sem o menu,
  # porque o flow 'inbound' não dispararia — trocar automação-demais por cliente-sem-atendimento.
  # Casos reais (AGN): conv 424 abre o ciclo com a pergunta do NPS; conv 449, com a fala do FLOW.
  # Reusa o vocabulário que o arquivo já fala (#automation_generated_message?, #nps_survey_message?)
  # em vez de inventar outro. Um TEMPLATE enviado pela agente NÃO é sistema: é a iniciativa dela —
  # exatamente o caso da conv 110, que tem de continuar barrando o flow 'inbound'.
  def human_initiated?(message)
    !automation_generated_message?(message) && !nps_survey_message?(message)
  end

  # A resolução não tem coluna própria na conversa: o registro estruturado dela é o ReportingEvent
  # 'conversation_resolved' (gravado sempre — o ReportingEventListener é incondicional no
  # async_dispatcher, e o bot_resolved é um `dup`, não um rename). Mesmíssima leitura que o
  # ReportingEventListener#conversation_opened já faz por conta própria em TODO reopen, e mais
  # barata: uma query no índice `index_reporting_events_on_conversation_id` (punhado de linhas por
  # conversa), resolvida sob demanda e só quando algum flow filtra por direção. `event_end_time` é
  # o instante SEMÂNTICO da resolução (created_at é quando a linha foi escrita, já assíncrono).
  def last_resolved_at(conversation)
    ReportingEvent.where(conversation_id: conversation.id, name: 'conversation_resolved').maximum(:event_end_time)
  end

  # Direção de uma MENSAGEM: incoming = entrada; qualquer outra (outgoing/template) = saída.
  def message_direction(message)
    message&.incoming? ? 'inbound' : 'outbound'
  end

  # Quando um AGENTE humano manda mensagem, ele assumiu a conversa: cancela os wait_for_reply
  # pendentes do flow. Sem isso, um menu que ficou pendente (o cliente nao escolheu opcao) captura
  # a PROXIMA resposta do cliente e responde "Nao entendi a opcao" — mesmo quando a resposta era
  # para o agente. Bug real (AGN): agente manda o template `continua_mensagem` -> cliente responde
  # "sim" -> um wait_for_reply de 2 dias atras resume e cai no fallback "nao entendi". Espelha o
  # NpsSurveyListener#dismiss_active_nps (agente assume -> encerra o fluxo do bot).
  # So mensagem de User HUMANO: o proprio flow manda outgoing sem sender User (e com flow_id).
  def cancel_pending_flow_waits_on_agent_reply(account, message)
    return if account.blank? || !flows_engine_active?(account)
    return unless human_agent_takeover?(message)

    cancel_pending_flow_waits(message.conversation_id)
  end

  # Idem, pelo caminho da ATRIBUICAO - mas SO quando esta PROVADO que um humano de carne e osso
  # assumiu. A guarda e POSITIVA de proposito, igual a do caminho por MENSAGEM logo acima: cancela
  # com prova de humano, em vez de "cancela sempre, a menos que...". A logica negativa era o defeito:
  # QUALQUER troca de responsavel matava o menu em espera, inclusive as AUTOMATICAS (o assign_agent
  # do proprio flow, o round-robin, o PeriodicAssignmentJob e o Motor de Distribuicao) - o cliente
  # ficava no meio do menu, algo assumia, e a resposta dele caia no vazio. Errar para o lado do
  # cancelamento mata conversa viva; errar para o outro lado so deixa o wait armado um pouco mais,
  # e o caminho por MENSAGEM captura o takeover real assim que o agente digita.
  #
  # Desatribuir (assignee_id -> nil) continua NAO cancelando: a conversa volta para a fila e o fluxo
  # do bot segue valendo.
  def cancel_pending_flow_waits_on_assignment(event)
    conversation = event.data[:conversation]
    return if conversation.blank? || conversation.assignee_id.blank?
    return unless human_assignment_takeover?(event)

    account = conversation.account
    return if account.blank? || !flows_engine_active?(account)

    cancel_pending_flow_waits(conversation.id)
  end

  # Ponto UNICO de cancelamento - os dois caminhos (mensagem e atribuicao) passam por aqui.
  def cancel_pending_flow_waits(conversation_id)
    FlowRun.where(conversation_id: conversation_id, status: :waiting).find_each(&:complete!)
  end

  # Prova de que um humano de carne e osso executou ESTA atribuicao.
  #
  # POR QUE `assignee_changed_by` e nao `performed_by`: `performed_by` e o `Current.executed_by`
  # (conversation.rb#dispatcher_dispatch), e ele SO e preenchido por quem executa automacao -
  # AutomationRule (automation_rules/action_service.rb), Flow (flows/action_service.rb) e
  # AssignmentPolicy/Inbox (auto_assignment/assignment_service.rb). O caminho humano nunca o seta:
  # o controller seta `Current.user` (application_controller.rb#set_current_user). Ou seja,
  # `performed_by` prova AUTOMACAO, nunca prova HUMANO - e chega NIL justamente nos dois casos que
  # precisamos separar: o agente atribuindo pela API E o Motor de Distribuicao
  # (Spx::Distribuicao::DistribuirService -> Conversations::AssignmentService), que roda DENTRO do
  # Sidekiq, onde o thread-local nasce zerado e portanto nao e nem AutomationRule nem Flow.
  #
  # `assignee_changed_by` e o proprio `Current.user`, capturado no contexto SINCRONO do request e
  # carregado no payload por AssignmentHandler#assignment_change_event_data - existe exatamente
  # porque aqui, no worker async (EventDispatcherJob/Sidekiq), `Current.user` ja e nil. Mesmo sinal,
  # com o mesmo `is_a?(User)`, que o NotificationListener#takeover_actor usa para decidir quem
  # "roubou" a conversa: automacao e round-robin passam nil, e token de AgentBot passa um nao-User.
  #
  # O contexto de automacao VENCE um `Current.user` ambiente (mesma regra do
  # Conversations::AssignmentHistoryService#derive_source): quando a automacao roda INLINE dentro de
  # um request — o motor de funil do Kanban re-entra sincrono, ver Current.funnel_automation_depth —
  # o payload sai com performed_by = AutomationRule E assignee_changed_by = o agente que apertou o
  # botao. Quem decidiu a atribuicao foi a regra, nao a pessoa: o menu nao pode morrer por isso.
  # `performed_by_automation?` cobre AutomationRule/Flow, que sao os unicos que re-entram sincrono;
  # AssignmentPolicy/Inbox so aparecem de dentro de job, onde `Current.user` ja e nil de qualquer jeito.
  def human_assignment_takeover?(event)
    return false if performed_by_automation?(event)

    event.data[:assignee_changed_by].is_a?(User)
  end

  # Mensagem que representa um agente HUMANO assumindo a conversa: outgoing, de User real, nao
  # privada e nao gerada pela automacao (o proprio flow manda outgoing com flow_id, nunca User).
  def human_agent_takeover?(message)
    return false unless message&.outgoing? && !message.private?
    return false unless message.sender_type == 'User' && message.sender.present?

    !automation_generated_message?(message)
  end

  # Consome uma mensagem incoming ANTES do disparo por-evento/keyword. Ordem importa: o opt-out
  # (compliance) vence a retomada. Devolve true quando a mensagem foi consumida (run_flows aborta).
  def incoming_message_consumed?(account, conversation, payload)
    handle_incoming_opt_out(account, conversation, payload) || resume_pending_reply(conversation, payload)
  end

  # Retoma um wait_for_reply pendente com esta mensagem incoming de contato; true só quando de fato
  # retomou. Mesmos filtros do keyword/opt-out (incoming, não-privada); anti-loop flow_id já aplicado
  # por ignore_message_created_event?.
  def resume_pending_reply(conversation, payload)
    message = payload[:message]
    return false unless message&.incoming? && !message.private?

    Flows::ReplyResumeService.new(conversation: conversation, reply: reply_from_message(message)).perform
  end

  # O reply { id, title } vem do selected_option (toque em botão/lista, id == o value da opção do
  # send_interactive) ou, sem ele, do próprio content (resposta digitada) — assim o wait_for_reply
  # casa tanto a escolha de opção quanto o texto livre.
  def reply_from_message(message)
    selected = message.content_attributes&.dig('selected_option')
    { id: selected&.dig('id') || message.content, title: selected&.dig('title') || message.content }
  end

  # Detecta e processa um opt-out numa mensagem INCOMING de contato. Ao casar, registra a
  # suppression de marketing (reason: opt_out) e devolve true — o run_flows aborta TODO disparo
  # por essa mensagem. Reusa os mesmos filtros de elegibilidade do keyword matcher (incoming,
  # não-privada); o anti-loop flow_id já foi aplicado por ignore_message_created_event?.
  def handle_incoming_opt_out(account, conversation, payload)
    message = payload[:message]
    return false unless message&.incoming? && !message.private?
    return false unless opt_out_message?(message.content)

    contact = conversation.contact
    ContactFlowSuppression.record_opt_out!(contact: contact, account: account) if contact.present?
    true
  end

  # É um pedido de descadastro? A mensagem, normalizada (transliterada, minúscula, colapsada) e
  # com a pontuação removida, é EXATAMENTE uma das OPT_OUT_KEYWORDS. Match exato (não substring)
  # evita falso-positivo em frases que só contêm a palavra. Ver #normalize_keyword.
  def opt_out_message?(content)
    normalized = normalize_keyword(content).gsub(/[^a-z0-9 ]/, '').strip
    OPT_OUT_KEYWORDS.include?(normalized)
  end

  def current_account_rules(event_name, account)
    cache_key = "automation_rules:#{account.id}:#{event_name}"
    rule_ids = Rails.cache.fetch(cache_key, expires_in: 2.minutes) do
      AutomationRule.where(event_name: event_name, account_id: account.id, active: true).pluck(:id)
    end
    AutomationRule.where(id: rule_ids)
  end

  # Casa o flow pelo evento. Multi-gatilho (F1-multi): o flow pode disparar em VÁRIOS eventos —
  # o canvas grava todos em `trigger_config.event_names` (array). Retrocompat: flows antigos têm
  # só `event_name` (string). Casa se o evento == event_name OU está contido em event_names.
  def current_account_flows(event_name, account)
    cache_key = "flows:#{account.id}:#{event_name}"
    flow_ids = Rails.cache.fetch(cache_key, expires_in: 2.minutes) do
      account.flows.active.conversation_event
             .where("trigger_config->>'event_name' = :ev OR trigger_config->'event_names' @> to_jsonb(:ev::text)",
                    ev: event_name)
             .pluck(:id)
    end
    Flow.where(id: flow_ids)
  end

  # Mesmo padrão de cache (2 min) dos flows por-evento — evita a query por mensagem. A lista
  # de keyword flows muda raramente; o matching case/acento-insensitive roda em memória.
  def current_account_keyword_flows(account)
    cache_key = "flows:#{account.id}:keyword"
    flow_ids = Rails.cache.fetch(cache_key, expires_in: 2.minutes) do
      account.flows.active.keyword.pluck(:id)
    end
    Flow.where(id: flow_ids)
  end

  # Casa o conteúdo da mensagem com as keywords do trigger_config, case- e acento-insensitive
  # (I18n.transliterate: "Olá" → "ola", como o normalize do WahaMessageResolvable). Modos:
  #   • 'exact'    → o conteúdo normalizado é IGUAL a alguma keyword
  #   • 'contains' → o conteúdo CONTÉM alguma keyword como substring (default)
  # Keywords em branco são descartadas; sem keyword válida, nunca casa.
  def keyword_trigger_match?(content, trigger_config)
    keywords = Array(trigger_config['keywords']).filter_map { |kw| normalize_keyword(kw).presence }
    return false if keywords.blank?

    haystack = normalize_keyword(content)
    return false if haystack.blank?

    if trigger_config['match'].to_s == 'exact'
      keywords.include?(haystack)
    else
      keywords.any? { |kw| haystack.include?(kw) }
    end
  end

  def normalize_keyword(text)
    I18n.transliterate(text.to_s).downcase.gsub(/\s+/, ' ').strip
  end

  # Reconhece tanto AutomationRule (motor antigo) quanto Flow (motor novo) como "sistema",
  # para não re-disparar sobre eventos que o próprio motor gerou.
  def performed_by_automation?(event)
    performer = event.data[:performed_by]
    performer.present? && (performer.instance_of?(AutomationRule) || performer.instance_of?(Flow))
  end

  def ignore_auto_reply_event?(event)
    conversation = event.data[:conversation]
    conversation.additional_attributes['auto_reply'].present?
  end

  def ignore_message_created_event?(event)
    message = event.data[:message]
    performed_by_automation?(event) || message.activity? || message.auto_reply_email? ||
      automation_generated_message?(message) || nps_survey_traffic?(message)
  end

  # Anti-loop de mensagem: ignora mensagens que o próprio motor criou. Checa a chave legada
  # `automation_rule_id` E a nova `flow_id` (generalização — Flows::ActionService marca as
  # mensagens com flow_id, action_service.rb).
  def automation_generated_message?(message)
    attrs = message.content_attributes || {}
    attrs['automation_rule_id'].present? || attrs['flow_id'].present?
  end

  # Tráfego da pesquisa NPS não é conversa e não deve mover automação: nem as mensagens que
  # o próprio NPS envia (pergunta = `nps_survey`; agradecimento/aviso/encerramento =
  # `nps_survey_system`), nem a resposta do cliente à pesquisa — que chega como incoming numa
  # conversa resolvida e dispararia flow de boas-vindas/LGPD + triagem em cima de quem só
  # respondeu "9". A resposta é reconhecida pelo NpsSurveys::ReopenGuard (mesma pergunta que
  # o Message#reopen_conversation faz) pra não divergir dele — este listener roda antes do
  # NpsSurveyListener no mesmo dispatch, então a pesquisa ainda está ativa aqui.
  def nps_survey_traffic?(message)
    return true if nps_survey_message?(message)

    message.incoming? && NpsSurveys::ReopenGuard.new(message: message).prevent_reopen?
  end

  # As mensagens que a PRÓPRIA pesquisa NPS emite, reconhecidas pelos marcadores que ela grava:
  # `nps_survey` (a pergunta) e `nps_survey_system` (agradecimento/aviso/encerramento). Só os
  # marcadores, de propósito — sem o ReopenGuard, que é a outra metade do #nps_survey_traffic?:
  # o guard pergunta pela pesquisa ATIVA AGORA (time-dependent) e cobra I/O, então não serve para
  # interrogar mensagens HISTÓRICAS, que é o que o scan do ciclo faz. Ver #human_initiated?.
  def nps_survey_message?(message)
    attrs = message.content_attributes || {}
    attrs['nps_survey'].present? || attrs['nps_survey_system'].present?
  end
end
