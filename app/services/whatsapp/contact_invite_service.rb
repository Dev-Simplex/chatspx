# Chama alguém no WhatsApp a partir de uma conversa em andamento. Dois casos, mesma
# mecânica: fora da janela de 24h a Meta só deixa INICIAR conversa por template (HSM).
#
#   mesma_pessoa: true  -> o próprio cliente em OUTRO número dele ("me chama nesse aqui").
#                          Ficha (ContactInbox) do número novo no MESMO contato e o
#                          contexto da conversa antiga vem junto — é o mesmo atendimento.
#   mesma_pessoa: false -> INDICAÇÃO: alguém que o cliente indicou (em geral por cartão de
#                          contato). Contato PRÓPRIO, conversa própria e NADA do contexto do
#                          indicador é copiado (é outra pessoa; o histórico não é dela).
#
# O inbound do WhatsApp resolve a conversa pela FICHA (Whatsapp::IncomingMessageBaseService
# #set_conversation) e o ContactInboxWithContactBuilder acha o contato pelo source_id, então
# quando a pessoa responder ela cai nesta conversa, já atribuída — sem duplicar ficha.
#
# Opt-in por conta (multi-tenant): account.settings['contact_invite'] =
# { enabled:, template_name:, language:, cooldown_hours:, referral_label: }. Sem config, no-op.
class Whatsapp::ContactInviteService # rubocop:disable Metrics/ClassLength
  Result = Struct.new(:ok, :error, :conversation, :phone, :contact_name, keyword_init: true)

  DEFAULT_LANGUAGE = 'pt_BR'.freeze
  DEFAULT_COOLDOWN_HOURS = 24
  INVITE_KEY = 'convite_whatsapp_em'.freeze
  # Controle do fio ANTIGO — não faz sentido carregar pro fio novo.
  SKIP_CONTEXT_KEYS = %w[followup_token followup_status followup_motivo followup_count
                         aguardando_humano_desde convite_whatsapp_em].freeze

  def initialize(conversation:, phone:, contexto:, nome: nil, mesma_pessoa: false)
    @origin = conversation
    @raw_phone = phone
    @contexto = contexto.to_s.strip.presence
    @nome = nome.to_s.strip.presence
    @mesma_pessoa = ActiveModel::Type::Boolean.new.cast(mesma_pessoa) || false
  end

  def perform
    reason = rejection
    return failure(reason) if reason

    target = target_conversation
    return failure(:alvo_em_atendimento) if target.blank?

    send_opener(target)
    stamp(target)
    Result.new(ok: true, conversation: target, phone: phone, contact_name: target.contact&.name)
  rescue StandardError => e
    Rails.logger.error("[ContactInvite] conv=#{origin.id} #{e.class}: #{e.message}")
    failure(:falha_envio)
  end

  private

  attr_reader :origin, :raw_phone, :contexto, :nome, :mesma_pessoa

  # Motivo pra NÃO enviar, ou nil quando está liberado.
  def rejection
    config_rejection || numero_rejection
  end

  def config_rejection
    return :desligado unless settings['enabled']
    return :sem_template if template_name.blank?
    return :canal_incompativel unless origin.inbox.channel.is_a?(Channel::Whatsapp)

    :sem_template_aprovado if template_body.blank?
  end

  def numero_rejection
    return :telefone_invalido if phone.blank?
    return :sem_contexto if contexto.blank?
    return :mesmo_numero if same_number?
    return :sem_nome if !mesma_pessoa && nome.blank?

    :convite_recente if invited_recently?
  end

  def failure(reason)
    Rails.logger.info("[ContactInvite] conv=#{origin.id} recusado: #{reason}")
    Result.new(ok: false, error: reason)
  end

  def settings
    @settings ||= (origin.account.settings['contact_invite'] || {}).with_indifferent_access
  end

  # A abertura do próprio cliente ("você pediu pra eu te chamar") não serve pra
  # indicação, então cada caso pode ter seu template; sem o de indicação, cai no padrão.
  def template_name
    chave = mesma_pessoa ? 'template_name' : 'referral_template_name'
    (settings[chave].presence || settings['template_name']).to_s
  end

  def language
    settings['language'].presence || DEFAULT_LANGUAGE
  end

  def inbox
    origin.inbox
  end

  # E.164 pelo mesmo normalizador do resto do fork (9º dígito, DDI, trunk-0).
  def phone
    return @phone if defined?(@phone)

    digits = raw_phone.to_s.gsub(/\D/, '')
    digits = "55#{digits}" if digits.length.between?(10, 11)
    candidate = "+#{digits}"
    normalized = Contacts::BrazilPhoneNormalizer.normalize(candidate) || candidate
    @phone = normalized.match?(/\A\+\d{10,15}\z/) ? normalized : nil
  end

  # Reusa a ficha que o WhatsApp já usa pro número (variantes 12d/13d) — mesma
  # reconciliação do disparo, pra não criar ficha duplicada.
  def source_id
    @source_id ||= Whatsapp::PhoneNumberNormalizationService
                   .new(inbox)
                   .normalize_and_find_contact_by_provider(phone.delete('+'), :cloud)
  end

  def same_number?
    atual = [origin.contact_inbox&.source_id, origin.contact&.phone_number].compact.map { |v| v.gsub(/\D/, '') }
    atual.include?(phone.delete('+'))
  end

  def invited_recently?
    last = origin.custom_attributes[INVITE_KEY]
    return false if last.blank?

    Time.zone.parse(last.to_s) > cooldown_hours.hours.ago
  rescue StandardError
    false
  end

  def cooldown_hours
    (settings['cooldown_hours'].presence || DEFAULT_COOLDOWN_HOURS).to_i
  end

  # Outro número do MESMO cliente: ficha nova no contato dele. Indicação: contato
  # próprio (reusa o cadastro se a pessoa já existir na conta).
  def contact_inbox
    @contact_inbox ||= if mesma_pessoa
                         inbox.contact_inboxes.find_by(source_id: source_id) ||
                           ContactInboxBuilder.new(contact: origin.contact, inbox: inbox, source_id: source_id).perform
                       else
                         ContactInboxWithContactBuilder.new(
                           inbox: inbox, source_id: source_id,
                           contact_attributes: { name: nome, phone_number: phone,
                                                 additional_attributes: { 'source' => 'indicacao' } }
                         ).perform
                       end
  end

  # Conversa DO FIO NOVO. Não passa pelo ConversationBuilder de propósito: com
  # lock_to_single ele devolveria a conversa do contato de origem e o HSM sairia pro
  # número ANTIGO — o destino é o source_id da ficha da conversa.
  # nil = alvo já está em atendimento (indicação que já é cliente de alguém).
  def target_conversation
    existing = contact_inbox.conversations.order(created_at: :desc).first
    return busy?(existing) ? nil : reopen(existing) if existing

    conversation = Conversation.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id,
      status: 'open',
      team_id: origin.team_id,
      custom_attributes: inherited_context,
      additional_attributes: additional_attributes
    )
    inherit_owner(conversation)
    apply_referral_label(conversation)
    # display_id vem de trigger no Postgres — sem reload ele é nil em memória e a nota
    # (e o retorno pro agente) sairiam sem o número da conversa.
    conversation.reload
  end

  # Indicação cuja conversa já está aberta e com dono é atendimento de outra pessoa:
  # não atropela com mensagem de abertura. No fio do próprio cliente, segue.
  def busy?(conversation)
    return false if mesma_pessoa

    !conversation.resolved? && (conversation.assignee_id.present? || conversation.assignee_agent_bot_id.present?)
  end

  def reopen(conversation)
    conversation.open! unless conversation.open?
    conversation.update!(custom_attributes: inherited_context.merge(conversation.custom_attributes))
    inherit_owner(conversation) if conversation.assignee_id.nil? && conversation.assignee_agent_bot_id.nil?
    conversation
  end

  # Indicação NÃO herda o contexto do indicador — o histórico é de outra pessoa.
  def inherited_context
    mesma_pessoa ? origin.custom_attributes.except(*SKIP_CONTEXT_KEYS) : {}
  end

  def additional_attributes
    if mesma_pessoa
      { 'source' => 'contact_invite', 'origin_conversation_id' => origin.id }
    else
      { 'source' => 'indicacao', 'indicado_por_conversation_id' => origin.id,
        'indicado_por_contact_id' => origin.contact_id }
    end
  end

  # Mesmo dono da conversa de origem (IA ou humano), pelo trilho canônico — assim o fio
  # novo não cai na triagem nem fica órfão, e a indicação fica com quem a recebeu.
  def inherit_owner(conversation)
    if origin.assignee_agent_bot_id.present?
      Conversations::AssignmentService.new(
        conversation: conversation, assignee_id: origin.assignee_agent_bot_id, assignee_type: 'AgentBot'
      ).perform
    elsif origin.assignee_id.present?
      Conversations::AssignmentService.new(conversation: conversation, assignee_id: origin.assignee_id).perform
    end
  end

  # Label opcional (config da conta) pro time filtrar de onde veio o lead.
  def apply_referral_label(conversation)
    label = settings['referral_label'].presence
    return if mesma_pessoa || label.blank?

    conversation.add_labels([label])
  rescue StandardError => e
    Rails.logger.warn("[ContactInvite] label falhou conv=#{conversation.id}: #{e.message}")
  end

  def template
    @template ||= (inbox.channel.message_templates || []).find do |tpl|
      tpl['name'] == template_name && tpl['status'] == 'APPROVED' && tpl['language'] == language
    end
  end

  def template_body
    @template_body ||= (template && (template['components'] || []).find { |c| c['type'] == 'BODY' })&.dig('text').to_s
  end

  # Quantas variáveis o template aprovado tem — o corpo dita o que mandamos.
  def template_vars
    @template_vars ||= begin
      values = { '1' => first_name, '2' => contexto.to_s }
      max = template_body.scan(/\{\{\s*(\d+)\s*\}\}/).flatten.map(&:to_i).max.to_i
      (1..max).to_h { |i| [i.to_s, values[i.to_s].to_s] }
    end
  end

  def first_name
    base = mesma_pessoa ? origin.contact&.name : nome
    base.to_s.strip.split.first.presence || 'tudo bem'
  end

  # Espelho na transcrição: o corpo aprovado com as variáveis já trocadas, pro time ver
  # no painel o que a pessoa recebeu.
  def preview
    template_vars.reduce(template_body) { |text, (index, value)| text.gsub(/\{\{\s*#{index}\s*\}\}/, value) }
  end

  def send_opener(conversation)
    params = { content: preview, content_type: :text, message_type: 'outgoing', private: false }
    # Só gasta HSM quando a janela de 24h está fechada — se a pessoa escreveu daquele
    # número há pouco, texto livre passa igual e sai mais barato.
    unless window_open?(conversation)
      params[:template_params] = { 'name' => template_name, 'language' => language,
                                   'processed_params' => { 'body' => template_vars } }
    end
    Messages::MessageBuilder.new(nil, conversation, params.with_indifferent_access).perform
  end

  def window_open?(conversation)
    conversation.messages.incoming.exists?(created_at: 24.hours.ago..)
  end

  # Cooldown na origem + rastro nas duas pontas, pro time entender o pulo de fio.
  def stamp(target)
    origin.update!(custom_attributes: origin.custom_attributes.merge(INVITE_KEY => Time.current.iso8601))
    note(origin, origin_note(target))
    note(target, target_note)
  end

  def origin_note(target)
    if mesma_pessoa
      "Mensagem enviada no outro número que o cliente pediu (#{phone}). O atendimento continua na conversa ##{target.display_id}."
    else
      "Indicação: #{target.contact&.name} (#{phone}) foi chamado no WhatsApp a partir desta conversa. Atendimento em ##{target.display_id}."
    end
  end

  def target_note
    if mesma_pessoa
      "Continuação do atendimento da conversa ##{origin.display_id} — o cliente pediu pra ser chamado neste número."
    else
      "Lead por indicação de #{origin.contact&.name} (conversa ##{origin.display_id})."
    end
  end

  def note(conversation, content)
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id,
      message_type: :outgoing, private: true, content: content
    )
  rescue StandardError => e
    Rails.logger.warn("[ContactInvite] nota falhou conv=#{conversation.id}: #{e.message}")
  end
end
