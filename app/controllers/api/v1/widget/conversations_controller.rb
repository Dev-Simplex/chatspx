class Api::V1::Widget::ConversationsController < Api::V1::Widget::BaseController
  include Events::Types
  before_action :render_not_found_if_empty, only: [:toggle_typing, :toggle_status, :set_custom_attributes, :destroy_custom_attributes]

  def index
    @conversation = conversation
  end

  def create
    # Bloco 2.15 — idempotencia do PRE-CHAT.
    #
    # Este endpoint cria CONVERSA e primeira mensagem no mesmo request, entao o
    # reenvio nao duplicava so uma frase: abria um segundo atendimento, com um
    # segundo contato identificado, para o mesmo visitante. `echo_id` ja era
    # permitido aqui e ja era gravado em `source_id` pelo `message_params` do
    # `BaseController` — faltava conferir antes de criar, que e o que a linha
    # abaixo faz.
    existing = existing_conversation_for_retry
    if existing
      @conversation = existing
      return
    end

    ActiveRecord::Base.transaction do
      process_update_contact
      @conversation = create_conversation
      conversation.messages.create!(message_params)
      # TODO: Temporary fix for message type cast issue, since message_type is returning as string instead of integer
      conversation.reload
    end
  end

  # PORTA 3 (bloco 4.16): este endpoint nao tem HMAC nenhum e nunca tera — o pre-chat e
  # digitado pelo visitante, que nao possui o segredo. O estado da inbox vai junto para que
  # a action recuse o MERGE sob enforcement estrito, sem recusar a conversa.
  def process_update_contact
    @contact = ContactIdentifyAction.new(
      contact: @contact,
      params: { email: contact_email, phone_number: contact_phone_number, name: contact_name, custom_attributes: contact_custom_attributes },
      retain_original_contact_name: true,
      discard_invalid_attrs: true,
      identity_enforcement: inbox&.resolved_identity_enforcement,
      verified_origin: @contact_inbox&.hmac_verified?
    ).perform
  end

  def update_last_seen
    head :ok && return if conversation.nil?

    conversation.contact_last_seen_at = DateTime.now.utc
    conversation.save!
    ::Conversations::UpdateMessageStatusJob.perform_later(conversation.id, conversation.contact_last_seen_at)
    head :ok
  end

  def transcript
    return head :too_many_requests if conversation.blank?
    return head :payment_required unless conversation.account.email_transcript_enabled?
    return head :too_many_requests unless conversation.account.within_email_rate_limit?

    send_transcript_email
    head :ok
  end

  def toggle_typing
    case permitted_params[:typing_status]
    when 'on'
      trigger_typing_event(CONVERSATION_TYPING_ON)
    when 'off'
      trigger_typing_event(CONVERSATION_TYPING_OFF)
    end

    head :ok
  end

  def toggle_status
    return head :forbidden unless @web_widget.end_conversation?

    unless conversation.resolved?
      conversation.status = :resolved
      conversation.save!
    end
    head :ok
  end

  def set_custom_attributes
    # Bloco 4.17: este endpoint nao tem assinatura nenhuma — e a superficie onde o site
    # escreve com mais liberdade. O portao recusa POR CHAVE, nunca a requisicao inteira, e
    # o valor protegido fica exatamente como estava.
    #
    # Bloco 5.08: e a escrita MESCLA. Era `update!(custom_attributes: recebidos)`, que
    # reescrevia o objeto inteiro — quem chegava depois apagava o que o outro lado tinha
    # gravado. Na 2a pagina o coletor de origem reenvia os `last_utm_*`/click ids e levava
    # junto as chaves que o proprio servidor derivou no `before_create` da conversa
    # (`Tracking::OriginRecorder`): `last_page_host`, `last_page_path`, `last_origin_kind` —
    # justamente por onde `Tracking::OriginReport` agrupa. Ninguem pediu para apagar, e
    # apagava.
    #
    # Por ser mescla, o portao usa `filter` e nao `replace`: chave protegida omitida nao
    # tem como sumir, porque o valor de antes sobrevive por construcao. A REMOCAO continua
    # existindo, e por onde sempre existiu — `destroy_custom_attributes`, que passa pela
    # porta `delete` do mesmo portao.
    gate = CustomAttributes::OriginGate.new(
      account: conversation.account,
      attribute_model: :conversation_attribute,
      verified: @contact_inbox&.hmac_verified?
    ).filter(permitted_params[:custom_attributes])

    conversation.update!(custom_attributes: (conversation.custom_attributes || {}).merge(gate.allowed))
    # B6: mesma historia do contato — sem definicao a chave nao renderiza no
    # painel (CustomAttributes.vue:76-89) nem entra no filtro.
    CustomAttributes::AutoProvisionService.new(
      account: conversation.account,
      attribute_model: :conversation_attribute,
      custom_attributes: gate.allowed
    ).perform
  end

  def destroy_custom_attributes
    # Bloco 4.17: apagar tambem e alterar. Este endpoint nao pede assinatura nenhuma, entao
    # sem o portao a chave protegida sai por aqui — quem nao consegue escrever, apaga.
    gate = CustomAttributes::OriginGate.new(
      account: conversation.account,
      attribute_model: :conversation_attribute,
      verified: @contact_inbox&.hmac_verified?
    ).delete(params[:custom_attribute])

    conversation.custom_attributes = conversation.custom_attributes.excluding(gate.allowed)
    conversation.save!
    render json: conversation
  end

  private

  def send_transcript_email
    return if conversation.contact&.email.blank?

    ConversationReplyMailer.with(account: conversation.account).conversation_transcript(
      conversation,
      conversation.contact.email
    )&.deliver_later
    conversation.account.increment_email_sent_count
  end

  def trigger_typing_event(event)
    Rails.configuration.dispatcher.dispatch(event, Time.zone.now, conversation: conversation, user: @contact)
  end

  def render_not_found_if_empty
    return head :not_found if conversation.nil?
  end

  # A conversa que ESTE mesmo pre-chat ja criou, se houver.
  #
  # O escopo sao as `conversations` do `BaseController`, que ja restringem a
  # sessao/contato desta requisicao: a chave de um visitante nunca devolve a
  # conversa de outro, nem por colisao nem por chave adivinhada.
  #
  # A busca vai em `Message`, e NAO em `conversations.joins(:messages)`, por dois
  # motivos independentes. O primeiro e que a associacao `Conversation#messages`
  # tem escopo dependente da instancia (`conversation.rb:168`) e `joins` sobre ela
  # levanta `ArgumentError` — 500 em todo pre-chat. O segundo e o que importa
  # depois que o primeiro esta resolvido: sob isolamento por time essa associacao
  # ESCONDE mensagens, e uma mensagem escondida faria a guarda nao encontrar a
  # chave e duplicar a conversa exatamente no caso que ela existe para evitar.
  def existing_conversation_for_retry
    echo_id = permitted_params[:message].try(:[], :echo_id)
    return if echo_id.blank?

    Message.find_by(conversation_id: conversations.select(:id), source_id: echo_id)&.conversation
  end

  def permitted_params
    params.permit(:id, :typing_status, :website_token, :email, contact: [:name, :email, :phone_number, { custom_attributes: {} }],
                                                               message: [:content, :referer_url, :timestamp, :echo_id],
                                                               custom_attributes: {})
  end
end
