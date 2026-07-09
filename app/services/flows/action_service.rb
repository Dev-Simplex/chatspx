# frozen_string_literal: true

# Funde os dois overrides existentes do ActionService num só. A base ActionService já
# traz ~13 ações compartilhadas + o mixin enterprise (add_sla/assign_ai_agent via
# ActionService.include_mod_with, action_service.rb:113); aqui unificamos o que divergia
# entre AutomationRules::ActionService (autor = nil + anti-loop) e Macros::ExecutionService
# (autor = actor + 'self'). A semântica depende do `actor`:
#   • actor presente  → macro-like  (disparo manual: autor = actor, permite assign_agent 'self')
#   • actor ausente   → automation-like (por evento: autor = nil, anti-loop via flow_id)
# O loop sobre os nós fica no Flows::RunnerService; aqui executamos UM nó por vez.
# Ver plano §2.4.
class Flows::ActionService < ActionService
  # Guardas de compliance (opt-out PARAR / cap de marketing / janela 24h) que
  # send_message/send_template chamam antes de enviar. Extraídas p/ manter esta classe enxuta.
  include Flows::Compliance
  # Nós de IA (Fase 3.2): ai_classify/ai_generate + helpers do Captain, extraídos p/ concern
  # (mesmo padrão do Flows::Compliance — mantém a classe enxuta). São ações ENTERPRISE, usam o
  # Captain como motor via Captain::Llm::AssistantChatService. Ver Flows::AiActions.
  include Flows::AiActions
  # snooze_conversation com DURAÇÃO opcional (override do base ActionService, que só faz snooze
  # indefinido). Extraído p/ concern pelo mesmo motivo dos acima — mantém a classe enxuta. Como o
  # módulo é incluído na subclasse, seu snooze_conversation precede o da superclasse ActionService.
  include Flows::SnoozeAction
  # add_participant: adiciona um agente como participante (seguidor) da conversa via o model
  # ConversationParticipant (idempotente). Concern pelo mesmo motivo dos acima.
  include Flows::ParticipantAction
  # enroll_in_sequence: inscreve a conversa numa Message Sequence (drip) via o serviço real
  # MessageSequences::EnrollService (idempotente).
  include Flows::SequenceAction
  # http_request: chamada HTTP(S) externa com guarda SSRF (bloqueia IP interno/metadata, fixa o
  # IP validado, sem redirect, timeout+cap). Ver o modelo de ameaça em Flows::HttpAction.
  include Flows::HttpAction
  # send_whatsapp_flow: envio de WhatsApp Flow interactive nativo. INTEGRAÇÃO PENDENTE (TODO
  # documentado em Flows::WhatsappFlowAction) — não está na whitelist/paleta; monta o payload
  # Meta e sinaliza um skip triável em vez de enviar errado.
  include Flows::WhatsappFlowAction

  # Outcome of ONE action node, consumed by the Flows::RunnerService to build a FlowStepLog.
  # `error` carries the captured exception (failed) or the Flows::StepSkip (skipped); nil on
  # success. Returned instead of raising so the walk stays best-effort AND leaves a trace.
  Result = Struct.new(:status, :error)

  def initialize(flow:, conversation:, actor: nil)
    super(conversation)
    @flow = flow
    @account = flow.account
    @actor = actor
    actor ? (Current.user = actor) : (Current.executed_by = flow)
  end

  # Executa UM nó `type:"action"`. Best-effort por nó (padrão de
  # automation_rules/action_service.rb:13-17): um erro num nó não derruba o fluxo — o Runner
  # segue para o próximo. Dispatch via `send` (métodos de ação são privados), nunca
  # `public_send`. Devolve um Result (success/failed/skipped) para o Runner registrar o passo;
  # NUNCA levanta. Um Flows::StepSkip (guarda intencional) é observável como `skipped` e NÃO
  # vai ao tracker; qualquer outro erro é capturado (Sentry) e reportado como `failed`.
  def execute(node)
    @conversation.reload
    action = node.with_indifferent_access
    send(action[:action_name], action[:action_params])
    Result.new(:success)
  rescue Flows::StepSkip => e
    Result.new(:skipped, e)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    Result.new(:failed, e)
  end

  private

  # nil no modo automação (mensagem "do sistema"); o actor no modo manual.
  def author
    @actor
  end

  # Anti-loop: marca as mensagens do motor com flow_id para o listener não re-disparar.
  # Generaliza automation_rules/action_service.rb:46. No modo manual (autor humano) não
  # há loop a evitar, então fica vazio (paridade com o macro, que não marca nada).
  def message_content_attributes
    @actor ? {} : { flow_id: @flow.id }
  end

  # 'self' só faz sentido no modo manual (macros/execution_service.rb:31-34); no modo
  # automação vira nil e é descartado.
  def assign_agent(agent_ids)
    agent_ids = agent_ids.filter_map { |id| id == 'self' ? @actor&.id : id }
    super(agent_ids)
  end

  def send_message(message)
    return if conversation_a_tweet?

    # Mensagem LIVRE (não-template): trata-se como `utility` (não-marketing) e exige a janela
    # de 24h — fora dela o WhatsApp só aceita template, então um texto livre seria rejeitado.
    # opt-out de marketing (PARAR) NÃO barra um texto de serviço; só uma suppression `all` barra.
    enforce_compliance!(category: 'utility', free_form: true)

    params = { content: message[0], private: false, content_attributes: message_content_attributes }
    Messages::MessageBuilder.new(author, @conversation.reload, params).perform
  end

  def add_private_note(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: true, content_attributes: message_content_attributes }
    Messages::MessageBuilder.new(author, @conversation.reload, params).perform
  end

  # Fonte do anexo é @flow.files (era @rule.files / @macro.files).
  def send_attachment(blob_ids)
    return if conversation_a_tweet?
    return unless @flow.files.attached?

    blobs = ActiveStorage::Blob.where(id: blob_ids)
    return if blobs.blank?

    params = { content: nil, private: false, attachments: blobs }
    Messages::MessageBuilder.new(author, @conversation.reload, params).perform
  end

  def send_webhook_event(webhook_url)
    payload = @conversation.webhook_data.merge(event: webhook_event_name)
    WebhookJob.perform_later(webhook_url[0], payload)
  end

  # Exclusivo da automação hoje (automation_rules/action_service.rb:57); no Flow vale para
  # ambos os modos porque a base é uma só.
  def send_email_to_team(params)
    teams = Team.where(id: params[0][:team_ids])
    teams.each do |team|
      break unless @account.within_email_rate_limit?

      TeamNotifications::AutomationNotificationMailer.conversation_creation(@conversation, team, params[0][:message])&.deliver_now
      @account.increment_email_sent_count
    end
  end

  def webhook_event_name
    event_name = @flow.trigger_config['event_name'].presence
    return 'flow.executed' if @actor || event_name.nil?

    "flow_event.#{event_name}"
  end

  # Envia um template WhatsApp aprovado (gap-BR nº1). A infra de envio já existe: basta
  # criar a mensagem outgoing com `template_params` — o Message resolve o Liquid dos
  # processed_params (Liquidable) e o SendOnWhatsappService entrega como template, dentro
  # OU fora da janela de 24h. Precedente: scheduled_messages/send_service.rb:43. Guards:
  # inbox whatsapp_cloud e template aprovado (no-op silencioso se ausente, padrão add_sla).
  def send_template(action_params)
    return if conversation_a_tweet?

    template = action_params[0].to_h.with_indifferent_access
    # Guardas do gap-BR: em vez do no-op silencioso (que sumia sem rastro), sinalizamos o
    # motivo tipado — o Runner registra um passo `skipped` triável, sem enviar ao Sentry.
    raise Flows::StepSkip.new('inbox_not_whatsapp', 'inbox is not a WhatsApp Cloud channel') unless whatsapp_cloud_inbox?
    raise Flows::StepSkip.new('template_not_approved', 'template is not approved on the inbox') unless approved_template?(template)

    # Compliance ANTES de montar/enviar. Categoria resolvida do metadata REAL do template
    # (MARKETING → marketing; resto → utility). Templates PODEM sair fora da janela de 24h (é o
    # propósito deles), por isso free_form:false — só o cap e o opt-out se aplicam aqui.
    enforce_compliance!(category: compliance_category(template), free_form: false)

    params = {
      message_type: 'outgoing',
      content: template['content'],
      template_params: {
        'name' => template['name'],
        'language' => template['language'],
        'processed_params' => template['processed_params'] || {}
      },
      content_attributes: message_content_attributes
    }
    Messages::MessageBuilder.new(author, @conversation.reload, params).perform
  end

  # Grava um atributo na conversa ou no contato (custom_attributes por padrão, ou
  # additional_attributes). O valor aceita Liquid ({{contact.name}}). Sem infra nova.
  # (set_attribute é um action_name do vocabulário, não um writer method.)
  def set_attribute(action_params) # rubocop:disable Naming/AccessorMethodName
    config = action_params[0].to_h.with_indifferent_access
    target = config['target'].to_s == 'contact' ? @conversation.contact : @conversation.reload
    key = config['key'].to_s
    return if target.blank? || key.blank?

    store = config['store'].to_s == 'additional' ? :additional_attributes : :custom_attributes
    current = target.public_send(store) || {}
    target.update!(store => current.merge(key => render_liquid(config['value'])))
  end

  # Move a conversa de etapa no Kanban reusando o MESMO caminho do board (arrastar cartão):
  # FunnelItems::MoveService — que sincroniza status open/resolved da etapa, faz o broadcast
  # em tempo real e dispara as automações declarativas do funil. action_params =
  # [{ funnel_id, stage_id }] (stage_id pode vir como 'stage'; funnel_id é opcional — sem
  # ele usamos o único/primeiro funil em que a conversa já está).
  # GUARD (risco real): se a conversa NÃO tem funnel_item, é no-op — nunca criamos uma
  # colocação do zero (isso plantaria a conversa num funil por conta do motor). Só movemos
  # cartões que já existem.
  def move_funnel_stage(action_params)
    config = action_params[0].to_h.with_indifferent_access
    stage_id = config['stage_id'].presence || config['stage'].presence
    return if stage_id.blank?

    funnel_item = existing_funnel_item(config['funnel_id'])
    return if funnel_item.blank?

    stage = funnel_item.funnel.funnel_stages.find_by(id: stage_id)
    return if stage.blank?

    FunnelItems::MoveService.new(
      conversation: @conversation.reload, funnel: funnel_item.funnel, funnel_stage: stage, moved_by: @actor
    ).perform
  end

  # Roda uma Macro existente (conjunto nomeado de ações) sobre a conversa atual. Em vez de
  # chamar Macros::ExecutionService — que faz `Current.reset` no ensure (corromperia o
  # Current.executed_by/flow_depth do walker em andamento) e cria mensagens SEM o marcador
  # flow_id (elas re-disparariam o listener → o próprio loop macro→flow→macro que o task
  # pede pra evitar) — despachamos as ações da macro pelo PRÓPRIO Flows::ActionService.
  # Assim herdam autoria e anti-loop (flow_id) idênticos aos demais nós.
  # GUARDS: macro inexistente/fora da conta → no-op; anti-recursão via Current.flow_depth
  # (mesmo contador do RunnerService) — no-op acima de MAX_DEPTH, barrando aninhamento
  # síncrono descontrolado.
  def call_macro(action_params)
    macro = @account.macros.find_by(id: Array(action_params).first)
    return if macro.blank?

    depth = Current.flow_depth || 0
    return if depth > Flows::RunnerService::MAX_DEPTH

    Current.flow_depth = depth + 1
    begin
      run_macro_actions(macro)
    ensure
      Current.flow_depth = depth
    end
  end

  # Best-effort por ação da macro (paridade com Macros::ExecutionService#perform e com o
  # nosso #execute): um erro numa ação não derruba as demais.
  def run_macro_actions(macro)
    Array(macro.actions).each do |macro_action|
      macro_action = macro_action.with_indifferent_access
      send(macro_action[:action_name], macro_action[:action_params])
    rescue Flows::StepSkip
      # Guarda intencional dentro da macro: no-op silencioso (paridade com a macro pura).
    rescue StandardError => e
      ChatwootExceptionTracker.new(e, account: @account).capture_exception
    end
  end

  # Dispara a pesquisa CSAT reusando o CsatSurveyService — o mesmo serviço que o
  # CsatSurveyListener usa ao resolver a conversa. Ele já carrega TODOS os guards do
  # produto (conversa resolvida, CSAT habilitado na inbox, dedup "não enviar duas vezes",
  # regras de rótulo, janela de mensagens, templates WhatsApp/Twilio). Sem params.
  def send_csat(_action_params = nil)
    return if conversation_a_tweet?

    CsatSurveyService.new(conversation: @conversation.reload).perform
  end

  # O único/primeiro funnel_item da conversa (por funnel_id quando informado). Retorna nil
  # quando a conversa não está em nenhum funil (ou não naquele funil) — a base do no-op.
  def existing_funnel_item(funnel_id)
    items = @conversation.reload.funnel_items
    funnel_id.present? ? items.find_by(funnel_id: funnel_id) : items.first
  end

  def whatsapp_cloud_inbox?
    channel = @conversation.inbox.channel
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'
  end

  def approved_template?(template)
    templates = @conversation.inbox.channel.message_templates
    templates.present? && templates.any? { |candidate| template_matches?(candidate, template) }
  end

  def template_matches?(candidate, template)
    candidate['name'] == template['name'] &&
      candidate['language']&.downcase == template['language']&.downcase &&
      candidate['status']&.downcase == 'approved'
  end

  def render_liquid(value)
    return value unless value.is_a?(String) && value.include?('{{')

    Liquid::Template.parse(value).render(liquid_drops)
  rescue Liquid::Error
    value
  end

  def liquid_drops
    {
      'contact' => ContactDrop.new(@conversation.contact),
      'conversation' => ConversationDrop.new(@conversation),
      'account' => AccountDrop.new(@account)
    }
  end
end
