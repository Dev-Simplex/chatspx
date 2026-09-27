# Abre a conversa com um lead do Captador em nome de quem clicou (22 §1.4).
#
# Por que não reusa o site_leads / Meta::LeadAds::CreateConversationService: aquele responde 200
# vazio e processa em job (o Captador não receberia ids), escreve sem usuário (as travas de time,
# agente e gate só rodam em controller) e casa contato por e-mail. Aqui o remetente é o usuário
# real e as travas são as do próprio fork, pelos mesmos concerns do ConversationsController.
#
# Caixa oficial (Channel::Whatsapp) só abre com modelo APROVADO, conferido antes de gravar: fora da
# janela de 24 h a Meta recusa texto livre. Caixa não oficial (Channel::Api, WAHA) manda o
# `preview` como texto livre, decisão do usuário ciente do risco ao número.
class Spx::Captador::LeadsController < Spx::Captador::BaseController
  include ConversationTeamAccessConcern
  include AgentConversationAccessConcern
  include ReusedConversationAccessConcern
  include ReplyAssignmentGateConcern

  BR_PHONE = /\A\+55[1-9]{2}\d{8,9}\z/
  PLACEHOLDER = /\{\{\s*([^}\s]+)\s*\}\}/
  IDEMPOTENCY_KEY = /\A[\w-]{8,128}\z/
  IDEMPOTENCY_TTL = 1.day.to_i

  class Rejected < StandardError
    attr_reader :status

    def initialize(status, error_code)
      @status = status
      super(error_code)
    end
  end

  rescue_from Rejected, with: ->(error) { render_error(error.status, error.message) }
  rescue_from ContactInboxBuilder::ConflictError, with: ->(error) { render_error(:conflict, 'contact_inbox_conflict', error.meta) }

  def create
    with_idempotency do
      load_records
      check_inbox
      phone = normalized_phone
      message = message_params.with_indifferent_access
      ActiveRecord::Base.transaction do
        open_conversation(phone)
        raise ActiveRecord::Rollback if performed?

        @message = Messages::MessageBuilder.new(Current.user, @conversation, message).perform
      end
      render_result unless performed?
    end
  end

  private

  def lead
    @lead ||= hash_param(:lead)
  end

  # Objeto JSON como Hash com acesso indiferente; qualquer outra coisa vira {} e cai na validação.
  def hash_param(key)
    value = params[key]
    value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : {}
  end

  # ---- pessoas e caixa ------------------------------------------------------------------------

  def load_records
    raise Rejected.new(:unprocessable_entity, 'invalid_payload') if lead[:id].blank?

    @actor = @account.users.find_by(id: params[:acting_user_id])
    @inbox = @account.inboxes.find_by(id: params[:inbox_id])
    # Sem dono explícito, o dono é quem clicou. Os concerns leem params[:assignee_id] e [:team_id].
    params[:assignee_id] = params[:assignee_id].presence || params[:acting_user_id]
    team_ok = params[:team_id].blank? || @account.teams.exists?(id: params[:team_id])
    raise Rejected.new(:not_found, 'not_found') unless @actor && @inbox && team_ok && @account.users.exists?(id: params[:assignee_id])

    Current.user = @actor
    Current.account_user = @account.account_users.find_by(user_id: @actor.id)
  end

  def check_inbox
    raise Rejected.new(:unprocessable_entity, 'channel_not_allowed') unless allowed_inbox? && (@inbox.whatsapp? || @inbox.api?)
    raise Rejected.new(:unprocessable_entity, 'inbox_read_only') if @inbox.read_only?
    # Equivale ao `authorize @inbox, :show?` do ConversationsController#inbox.
    raise Rejected.new(:forbidden, 'inbox_access_denied') unless @actor.assigned_inboxes(@account).exists?(id: @inbox.id)
  end

  def allowed_inbox?
    @hook.settings['allowed_inbox_ids'].to_s.split(',').map(&:strip).include?(@inbox.id.to_s)
  end

  # ---- mensagem -------------------------------------------------------------------------------

  def message_params
    base = { message_type: 'outgoing', private: false, echo_id: "captador:#{idempotency_key}" }
    return base.merge(content: free_text) unless @inbox.whatsapp?

    template = approved_template
    base.merge(content: params[:preview].presence || rendered_body(template), template_params: template_params)
  end

  def free_text
    params[:preview].presence || raise(Rejected.new(:unprocessable_entity, 'content_required'))
  end

  def requested_template
    @requested_template ||= hash_param(:template)
  end

  # Mesma busca do Whatsapp::TemplateProcessorService#find_template.
  def approved_template
    template = Array(@inbox.channel.message_templates).find do |candidate|
      candidate['name'] == requested_template[:name] &&
        candidate['language'].to_s.casecmp?(requested_template[:language].to_s) &&
        candidate['status'].to_s.casecmp?('approved')
    end
    raise Rejected.new(:unprocessable_entity, 'template_not_approved') unless template
    # Variável a mais ou a menos no corpo é o erro 132000 da Meta, que só apareceria depois do envio.
    raise Rejected.new(:unprocessable_entity, 'template_params_mismatch') unless body_placeholders(template).sort == body_params.keys.sort

    template
  end

  def body_text(template)
    Array(template['components']).find { |component| component['type'].to_s.casecmp?('body') }&.dig('text').to_s
  end

  def body_placeholders(template)
    body_text(template).scan(PLACEHOLDER).flatten.uniq
  end

  def body_params
    body = requested_template.dig(:processed_params, :body)
    body.is_a?(Hash) ? body.to_h.transform_keys(&:to_s) : {}
  end

  def rendered_body(template)
    body_text(template).gsub(PLACEHOLDER) { body_params[Regexp.last_match(1)].to_s }
  end

  def template_params
    {
      'name' => requested_template[:name],
      'language' => requested_template[:language],
      'processed_params' => requested_template[:processed_params] || {}
    }
  end

  # ---- contato e conversa ---------------------------------------------------------------------

  # Zero de tronco fora, 55 quando falta, 9º dígito pelo normalizador do fork.
  def normalized_phone
    digits = lead[:telefone].to_s.gsub(/\D/, '').sub(/\A0+/, '')
    digits = "55#{digits}" if digits.length.between?(10, 11)
    phone = Contacts::BrazilPhoneNormalizer.normalize("+#{digits}")
    raise Rejected.new(:unprocessable_entity, 'phone_invalid') unless phone.match?(BR_PHONE)

    phone
  end

  def open_conversation(phone)
    contact = contact_for(phone)
    check_contact(contact)
    @conversation = existing_conversation(contact) || ConversationBuilder.new(params: conversation_params, contact_inbox: @contact_inbox).perform
    @new_conversation = @conversation.previously_new_record?

    adopt_or_block_reused_conversation
    return if performed?

    self_assign_creator_for_reply_gate
    enforce_reply_assignment_gate
    return if performed?

    @conversation.open! if @conversation.resolved?
    stamp(contact)
  end

  # Só nome e telefone: o builder casa primeiro por identifier e e-mail, e a caixa Cloud tira o
  # source_id do telefone do contato ACHADO. Com e-mail compartilhado (contabilidade, grupo de
  # empresas), a abertura iria para o número de outra empresa.
  def contact_for(phone)
    @contact_inbox = ContactInboxWithContactBuilder.new(
      inbox: @inbox, contact_attributes: { name: lead[:nome].to_s.strip, phone_number: phone }, source_id: source_id_for(phone)
    ).perform
    @contact_inbox.contact
  end

  # Mesmo formato do inbound de cada canal, para reusar a ficha em que o cliente responde
  # (Meta::LeadAds::CreateConversationService#source_id_for).
  # ponytail: caixa API sem sessão WAHA ganha uma ficha nova (uuid) a cada envio; a conversa é
  # achada por contato, então só sobra ficha. Resolver quando alguém usar caixa API sem WAHA.
  def source_id_for(phone)
    digits = phone.delete('+')
    return Whatsapp::PhoneNumberNormalizationService.new(@inbox).normalize_and_find_contact_by_provider(digits, :cloud) if @inbox.whatsapp?

    "#{digits}@c.us" if @inbox.waha_session_name.present?
  end

  def check_contact(contact)
    raise Rejected.new(:unprocessable_entity, 'contact_opted_out') if ContactFlowSuppression.suppressed?(contact, 'marketing')
    return unless contact.blocked? || contact.custom_attributes&.dig('whatsapp_number_exists') == false

    raise Rejected.new(:unprocessable_entity, 'whatsapp_number_invalid')
  end

  # Regra do motor de leads: a última conversa não resolvida do contato nesta caixa.
  def existing_conversation(contact)
    Conversation.where(inbox_id: @inbox.id, contact_id: contact.id).where.not(status: :resolved).order(created_at: :desc).first
  end

  def conversation_params
    ActionController::Parameters.new(assignee_id: params[:assignee_id], team_id: params[:team_id].presence, status: 'open')
  end

  # Cópia do ConversationsController#self_assign_creator_for_reply_gate (privado lá). Diferente do
  # `create` da API, aqui o gate roda depois também na conversa reutilizada: é envio frio.
  def self_assign_creator_for_reply_gate
    return unless Current.account.reply_assignment_gate_enabled?
    return if @conversation.assignee_id.present?

    @conversation.update!(assignee_id: Current.user.id)
  end

  # Atributos por merge e label por união: nada do que a conversa ou o contato já tinham se perde.
  def stamp(contact)
    lead_id = lead[:id].to_s
    lead_url = "#{@hook.settings['captador_url'].to_s.chomp('/')}/leads/#{lead_id}"
    @conversation.update!(custom_attributes: (@conversation.custom_attributes || {}).merge('captador_lead_id' => lead_id, 'captador_url' => lead_url))
    @conversation.add_labels([Crm::Captador::SetupService::LABEL])

    contact.custom_attributes = (contact.custom_attributes || {}).merge({ 'captador_lead_id' => lead_id, 'cnpj' => lead[:cnpj].presence }.compact)
    contact.email = lead_email if contact.email.blank? && lead_email && !@account.contacts.exists?(email: lead_email)
    contact.save!
  end

  # E-mail que não passaria na validação do Contact vira nil: um e-mail ruim não derruba o envio.
  def lead_email
    email = lead[:email].to_s.strip.downcase
    email if email.match?(Devise.email_regexp)
  end

  # ---- resposta e idempotência ----------------------------------------------------------------

  def render_result
    render json: {
      contact_id: @conversation.contact_id,
      conversation_id: @conversation.display_id,
      message_id: @message.id,
      reused: !@new_conversation,
      conversation_url: "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{@account.id}/conversations/#{@conversation.display_id}"
    }, status: @new_conversation ? :created : :ok
  end

  def idempotency_key
    request.headers['Idempotency-Key'].to_s
  end

  # A mesma chave com o mesmo corpo devolve a resposta guardada, sem segunda mensagem; com outro
  # corpo, ou enquanto o primeiro pedido ainda roda, 409. Erro não fica guardado: o Captador pode
  # corrigir e repetir com a mesma chave. Segunda defesa: o echo_id da mensagem (MessageBuilder).
  def with_idempotency
    return render_error(:bad_request, 'idempotency_key_required') unless idempotency_key.match?(IDEMPOTENCY_KEY)

    key = "spx:captador:idempotency:#{@account.id}:#{idempotency_key}"
    digest = Digest::SHA256.hexdigest(request.raw_post)
    return replay(key, digest) unless Redis::Alfred.set(key, { digest: digest }.to_json, nx: true, ex: IDEMPOTENCY_TTL)

    begin
      yield
    rescue StandardError
      Redis::Alfred.delete(key)
      raise
    end
    remember(key, digest)
  end

  def remember(key, digest)
    return Redis::Alfred.delete(key) unless response.successful?

    Redis::Alfred.set(key, { digest: digest, status: response.status, body: JSON.parse(response.body) }.to_json, ex: IDEMPOTENCY_TTL)
  end

  def replay(key, digest)
    stored = JSON.parse(Redis::Alfred.get(key) || '{}')
    return render_error(:conflict, 'idempotency_conflict') unless stored['digest'] == digest && stored['status']

    render json: stored['body'], status: stored['status']
  end
end
