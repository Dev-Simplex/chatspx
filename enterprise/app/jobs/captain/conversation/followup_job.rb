class Captain::Conversation::FollowupJob < ApplicationJob
  queue_as :low

  MAX_FOLLOWUPS = 4

  # Faixa de descanso. Antes era 21h→8h, e cobria duas faixas em que o cliente está acordado:
  # medido em 14 dias numa conta, as mensagens DELE por hora dão 21h=242, 22h=156, 23h=99,
  # 0h–5h≈114 no total, 6h=157 e **7h=667** — às 7h há mais movimento que às 18h. Silenciar
  # 21h–8h calava a cutucada justamente onde havia conversa.
  QUIET_START = 22
  QUIET_END = 7

  # Dentro da faixa de descanso a cutucada não é proibida: ela desacelera. Quem escreveu há
  # pouco está com o telefone na mão — silenciar alguém que acabou de falar com a gente às 23h
  # é pior que responder. O que não pode é insistir de madrugada com quem já dormiu.
  CLIENTE_ATIVO_EM = 60.minutes
  # Intervalo mínimo entre cutucadas dentro da faixa. Fora dela, quem manda é o tempo que o
  # agente escolheu (que pode ser 5 minutos num lead quente).
  CADENCIA_NOTURNA = 45.minutes

  # Cutucada decidida pelo agente (via ProgramarFollowupTool). Dispara só se ainda
  # fizer sentido: token atual, dono da conversa ainda é a IA, cliente não respondeu,
  # dentro de horário civilizado. A própria cutucada é gerada pelo agente no contexto.
  def perform(conversation, token) # rubocop:disable Metrics/CyclomaticComplexity
    return if conversation.inbox.read_only? # CHAT-155
    return unless followup_due?(conversation, token)

    # Dono resolvido ANTES de consumir token/followup_count (gate por atribuição, D-6):
    # se a cutucada não vai sair, não se gasta tentativa nem se invalida o token (token
    # órfão é inofensivo — o próximo ProgramarFollowupTool o substitui). A cutucada sai
    # do dono ATUAL da conversa (não da inbox) — transferência IA→IA mid-followup faz a
    # cutucada sair com a voz da IA nova.
    assistant = owner_assistant(conversation)
    return desistir_do_compromisso(conversation, token) unless assistant # dono não é IA -> morre SEM consumir token/count
    return travado_pela_trava_de_teste(conversation, token, assistant) unless contato_liberado?(conversation, assistant)

    attrs = conversation.custom_attributes || {}
    count = attrs['followup_count'].to_i
    return cool_down_lead(conversation, attrs, assistant) if count >= MAX_FOLLOWUPS

    # O compromisso e CONSUMIDO aqui (motivo lido antes de zerar): cumprido uma vez, nao pode
    # vazar pras cutucadas preventivas seguintes, que passariam a se achar compromisso tambem.
    # A `janela` sai pelo mesmo motivo — senao a isencao da faixa de descanso, que existe pro
    # horario que o cliente pediu, ficaria valendo pra toda cutucada seguinte da conversa. Ela
    # nao e apagada: vira `_cumprida`, que preserva o rastro sem continuar mandando no relogio.
    motivo = attrs['followup_motivo']
    consumidos = { 'followup_count' => count + 1, 'followup_token' => nil, 'followup_motivo' => nil }
    consumidos['followup_janela'] = nil
    consumidos['followup_janela_cumprida'] = attrs['followup_janela'] if attrs['followup_janela'].present?
    conversation.update!(custom_attributes: attrs.merge(consumidos))
    Captain::Conversation::ResponseBuilderJob.perform_now(conversation, assistant, directive: directive(motivo))
  end

  private

  def followup_due?(conversation, token)
    return false unless conversation

    conversation.reload
    attrs = conversation.custom_attributes || {}
    return false unless attrs['followup_token'] == token           # substituído por outro follow-up
    return desistir_do_compromisso(conversation, token) if desistencia?(conversation, attrs)
    return false if cancelado_por_resposta?(conversation, attrs)
    return false if reschedule_if_quiet_hours(conversation, token, attrs) # noite -> desacelera ou adia

    true
  end

  # Travas que matam a cutucada de vez (não adiam): resolvida/esperando humano, ou fora da
  # janela (não é cutucada). Checadas antes de cancelado_por_resposta?, o que não muda nada:
  # aquele só cancela sem compromisso, e aí não há o que descartar.
  #
  # Agendada da IA esperando o horário do cliente (CHAT-165) também mata: ela cumpre o combinado,
  # e cutucar antes é insistir com quem já disse quando quer falar.
  def desistencia?(conversation, attrs)
    followup_pointless?(conversation, attrs) || janela_fechada?(conversation) ||
      ScheduledMessage.agendada_da_ia_pendente?(conversation)
  end

  # Desistência (trava, não adiamento): o compromisso não vai ser cumprido por ESTE job, então
  # ele sai do registro. Pendurado, o followup_motivo fazia o ja_tem_destino? do
  # ResponseBuilderJob bloquear toda cutucada automática seguinte — a conversa nunca mais era
  # cutucada (medido: 201 conversas ativas com motivo órfão). Token e followup_count ficam como
  # estão (cutucada que não sai não gasta tentativa); a quiet hours NÃO passa por aqui, porque
  # remarca o mesmo job, que ainda vai cumprir. Sob lock e com o token conferido de novo, pra
  # não apagar o compromisso de um follow-up mais novo gravado no meio do caminho. Devolve
  # false para servir de retorno de followup_due?.
  def desistir_do_compromisso(conversation, token)
    conversation.with_lock do
      attrs = conversation.custom_attributes || {}
      next unless attrs['followup_token'] == token && compromisso?(attrs)

      conversation.update!(custom_attributes: attrs.merge('followup_motivo' => nil, 'followup_janela' => nil))
    end
    false
  end

  # BORDA DA JANELA (contrato do eixo, regra 1). Cutucada é engrenagem in-window: fora da janela
  # quem bate na porta é a repescagem — template pago, escolhido pelo operador —, que ainda não
  # existe. Texto livre lá fora não vira repescagem disfarçada; vira envio recusado pelo canal.
  #
  # Morre DEFINITIVO, não remarca como as quiet hours: a manhã chega sozinha, a janela não. Só a
  # resposta do cliente reabre (template não reabre), e a cutucada é justamente o que não pode
  # causar esse evento — remarcar seria esperar por si mesma. Se o cliente voltar, o turno dele
  # rearma uma cutucada nova pelo auto_schedule_followup — o que só vale porque a desistência
  # limpa o followup_motivo (senão o ja_tem_destino? bloquearia o rearme).
  #
  # Fica em followup_due?, antes de tudo, por dois motivos: (a) mantém o princípio do arquivo —
  # cutucada que não sai não gasta token nem followup_count. O compromisso (followup_motivo),
  # porém, é descartado (desistir_do_compromisso): armado, ele bloqueava a cutucada automática
  # quando o cliente voltasse, e a forma-template que o cumpriria fora da janela não existe;
  # (b) é o único ponto que também barra o cool_down_lead, cuja escalada termina em
  # MessageTemplates::Template::OutOfOffice, que cria mensagem SEM checar can_reply? — parar na borda "sem cair em outro caminho de envio" exige
  # cortar antes dele. Vem antes do reschedule pra não gastar job remarcando o que já morreu.
  #
  # can_reply? devolve TRUE quando o canal não tem janela configurada, e isso é de propósito:
  # senão a guarda calaria a cutucada em canal sem janela nenhuma. Ele já ancora na última
  # mensagem do CLIENTE, que é a âncora certa (regra 3).
  def janela_fechada?(conversation)
    !conversation.can_reply?
  end

  # Cliente respondeu -> não cutuca. EXCETO com compromisso pendente: aí a última mensagem dele
  # costuma ser justamente a despedida educada que fechou o assunto socialmente sem cumprir o
  # combinado — e era ela que matava a cutucada (conv 20320).
  def cancelado_por_resposta?(conversation, attrs)
    lead_replied?(conversation) && !compromisso?(attrs)
  end

  # Compromisso = a cutucada foi programada pelo agente pra cumprir algo que ficou combinado,
  # não é sobrevida preventiva. O followup_motivo grava isso e só a ProgramarFollowupTool o
  # escreve — o auto-agendamento nunca o seta, então ele distingue os dois tipos de cutucada.
  #
  # ⚠️ Isto NÃO quer dizer que o cliente marcou a hora: `motivo` é obrigatório na ferramenta,
  # então toda cutucada que o agente programa tem motivo. Quem marca a hora é a `janela`, e é
  # ela que responde por horario_do_cliente? — não confundir os dois.
  def compromisso?(attrs)
    attrs['followup_motivo'].present?
  end

  # O cliente disse a hora ("me chama às 21h30", "quinta de manhã") e a ferramenta gravou a fala
  # dele em followup_janela. Aí o relógio é dele: adiar pra manhã transformaria a promessa num
  # atraso de dez horas, e quem pediu 21h30 está acordado às 21h30.
  def horario_do_cliente?(attrs)
    attrs['followup_janela'].present?
  end

  # Resolvida, ou esperando atendente humano (Modelo A): cutucar só atrapalha.
  def followup_pointless?(conversation, attrs)
    conversation.resolved? || attrs['aguardando_humano_desde'].present?
  end

  # Espelho captain dono da conversa -> assistant; humano/webhook-bot/sem dono -> nil.
  def owner_assistant(conversation)
    mirror = conversation.assignee_agent_bot
    return unless mirror&.captain?

    mirror.captain_assistant
  end

  # Trava de teste do assistente (CHAT-171): contato fora de only_contact_phones não recebe
  # cutucada nem a escalada do cool_down_lead. A IA pode seguir dona de uma conversa atribuída
  # ANTES de a trava ser ligada, e o router só barra a resposta a mensagem nova — a cutucada já
  # armada passava por fora (CHAT-213). Morre como desistência: sem gastar token nem contagem.
  def contato_liberado?(conversation, assistant)
    Captain::Behavior::ContactPhoneLock.new(assistant).allows?(conversation.contact)
  end

  def travado_pela_trava_de_teste(conversation, token, assistant)
    Captain::AssistantLog.create!(captain_assistant: assistant, conversation: conversation, event_type: 'router_skip',
                                  payload: { 'motivo' => 'trava_de_teste', 'origem' => 'followup' })
    desistir_do_compromisso(conversation, token)
  end

  # Esgotou as cutucadas in-window e o cliente segue sem responder: em vez de só esfriar,
  # ESCALA pra um humano tentar recuperar o lead que a IA não converteu. Vai pelo mesmo
  # caminho do handoff do agente (HumanHandoffService: abre, roteia pro time, marca
  # `aguardando_humano_desde` -> a IA para de cutucar e de responder). Substitui a cadência
  # de reativação por HSM: quem conduz o lead frio passa a ser a pessoa, não um automático.
  def cool_down_lead(conversation, attrs, assistant)
    conversation.update!(custom_attributes: attrs.merge(
      'tozi_status_lead' => 'esfriado',
      'followup_status' => 'esgotou cutucadas -> encaminhado pra humano',
      'followup_token' => nil,
      # Quem conduz o lead agora é a pessoa: o compromisso vai junto no dossiê, não fica
      # armado no registro segurando a cadência da IA.
      'followup_motivo' => nil,
      'followup_janela' => nil
    ))
    Spx::Tozi::FunnelPlacementService.move(conversation: conversation, to: 'frio')
    Captain::Conversation::HumanHandoffService.new(conversation: conversation, assistant: assistant).perform
  end

  def directive(motivo)
    return directive_compromisso(motivo) if motivo.present?

    '[NOTA INTERNA — não é mensagem do cliente, não repita este texto] O cliente parou de responder no meio ' \
      'do atendimento. Sua função aqui é RETOMAR: mande UMA cutucada curta, natural e diferente do que você já ' \
      'disse, puxando de onde parou (a última pergunta ou proposta que ficou sem resposta). NÃO cutuque (responda ' \
      'só [IGNORAR]) apenas nestes casos claros: a última mensagem DELE disse que ia retornar, pensar, ver ou ' \
      'falar com alguém, pediu um tempo, encerrou ou agradeceu; OU você já mandou uma cutucada parecida nesta ' \
      'conversa (nunca repita a mesma pergunta); OU realmente não há nada pendente. Fora desses casos, cutuque — ' \
      'não deixe o lead esfriar por excesso de cautela.'
  end

  # Com compromisso pendente a lista de [IGNORAR] NÃO pode conter "encerrou ou agradeceu": foi
  # por aí que a 20320 morreu — a cliente se despediu com educação e a cutucada que existia pra
  # cumprir o combinado se calou. O que cancela aqui é o combinado já ter sido cumprido, não a
  # conversa ter fechado socialmente.
  def directive_compromisso(motivo)
    '[NOTA INTERNA — não é mensagem do cliente, não repita este texto] Ficou um COMPROMISSO pendente nesta ' \
      "conversa e chegou a hora combinada de retomá-lo: #{motivo}. Retome esse ponto com UMA mensagem curta e " \
      'natural, mesmo que a conversa tenha se encerrado socialmente — uma despedida ou um agradecimento do ' \
      'cliente NÃO desmarca o que ficou combinado. Responda só [IGNORAR] se o combinado já foi cumprido nesta ' \
      'conversa, se você já cobrou este mesmo ponto antes, ou se o cliente pediu pra não ser mais procurado.'
  end

  def lead_replied?(conversation)
    last = conversation.messages.where(message_type: %i[incoming outgoing], private: false).order(:created_at).last
    last.nil? || last.message_type == 'incoming'
  end

  # Devolve true quando a cutucada NÃO deve sair agora (o job foi remarcado).
  #
  # A faixa de descanso não silencia mais: ela desacelera. Três saídas, nesta ordem:
  #
  #   1. HORÁRIO PEDIDO PELO CLIENTE passa direto ("me chama às 21h30"): cumprir o combinado no
  #      horário combinado é o oposto de incomodar. Note que o critério é a `janela`, não o
  #      `motivo` — toda cutucada da ferramenta tem motivo, e usá-lo aqui furaria a faixa
  #      inteira em vez de abrir a exceção.
  #   2. CLIENTE ACORDADO recebe, com espaçamento maior. Quem escreveu há pouco está com o
  #      telefone na mão; calar às 23h alguém que acabou de falar com a gente é sumir no meio da
  #      conversa. O que muda é o ritmo: a cutucada respeita CADENCIA_NOTURNA contada da última
  #      mensagem DELE, em vez do intervalo curto que o agente escolheu.
  #   3. QUEM JÁ DORMIU espera a manhã. Como a régua é a última mensagem do cliente, isso se
  #      resolve sozinho: a 1ª cutucada da noite sai, e se ele não responder, a 2ª já o encontra
  #      fora de CLIENTE_ATIVO_EM e cai pro dia seguinte. Uma por noite, no máximo.
  def reschedule_if_quiet_hours(conversation, token, attrs)
    return false if horario_do_cliente?(attrs)

    now = Time.current.in_time_zone(fuso)
    return false unless faixa_de_descanso?(now)

    espera = espera_noturna(conversation, now)
    return false if espera.nil?

    self.class.set(wait: espera).perform_later(conversation, token)
    true
  end

  def faixa_de_descanso?(now)
    now.hour >= QUIET_START || now.hour < QUIET_END
  end

  # nil = pode cutucar agora. Caso contrário, quanto esperar.
  def espera_noturna(conversation, now)
    ultima = ultima_fala_do_cliente(conversation)
    return proxima_manha(now) - now if ultima.nil? || (now - ultima) > CLIENTE_ATIVO_EM

    proxima = ultima + CADENCIA_NOTURNA
    return nil if proxima <= now

    # Se o espaçamento jogaria a cutucada pra depois do fim da faixa, a manhã resolve — e
    # chegar às 7h01 é melhor que chegar às 6h58.
    [proxima - now, proxima_manha(now) - now].min
  end

  def proxima_manha(now)
    now.hour >= QUIET_START ? now.tomorrow.change(hour: QUIET_END) : now.change(hour: QUIET_END)
  end

  def ultima_fala_do_cliente(conversation)
    conversation.messages.where(message_type: :incoming, private: false).maximum(:created_at)
  end

  def fuso
    ActiveSupport::TimeZone['America/Cuiaba'] || ActiveSupport::TimeZone['UTC']
  end
end
