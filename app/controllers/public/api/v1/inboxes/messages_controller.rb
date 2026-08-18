class Public::Api::V1::Inboxes::MessagesController < Public::Api::V1::InboxesController
  # Lista de transmissao. A app `chatwoot` da WAHA injeta o prefixo de autor
  # quando `isJidGroup(chatId) || isJidBroadcast(chatId)` — ou seja, grupo E
  # broadcast. O `Conversation#group?` (contrato C1) cobre so `@g.us`.
  WHATSAPP_BROADCAST_JID_SUFFIX = '@broadcast'.freeze

  before_action :set_message, only: [:update]

  def index
    @messages = @conversation.nil? ? [] : message_finder.perform
  end

  def create
    return head :ok if @contact_inbox&.contact&.blocked?

    @message = @conversation.messages.new(message_params)
    build_attachment
    @message.save!
    schedule_group_sender_phone_resolution
  end

  def update
    return handle_waha_message_update if waha_update?

    render json: { error: 'You cannot update the CSAT survey after 14 days' }, status: :unprocessable_entity and return if check_csat_locked

    @message.update!(message_update_params)
  rescue StandardError => e
    render json: { error: @contact.errors, message: e.message }.to_json, status: :internal_server_error
  end

  private

  def waha_update?
    params[:source_id].present? || params[:status].present?
  end

  def handle_waha_message_update
    @message.update!(source_id: params[:source_id]) if params[:source_id].present? && @message.outgoing? && @message.source_id.blank?
    Messages::StatusUpdateService.new(@message, params[:status]).perform if params[:status].present?
    head :ok
  end

  def build_attachment
    return if params[:attachments].blank?

    params[:attachments].each do |uploaded_attachment|
      # A shared contact (.vcf) becomes one or more rich contact cards instead
      # of a generic download bubble. Falls back to a normal file attachment
      # when it isn't a vCard or can't be parsed.
      next if Vcard::ContactAttachmentService.new(message: @message, uploaded_file: uploaded_attachment).build

      @message.attachments.new(
        account_id: @message.account_id,
        file_type: helpers.file_type(uploaded_attachment&.content_type),
        file: uploaded_attachment
      )
    end
  end

  def message_finder_params
    {
      filter_internal_messages: true,
      before: params[:before]
    }
  end

  def message_finder
    @message_finder ||= MessageFinder.new(@conversation, message_finder_params)
  end

  def message_update_params
    params.permit(submitted_values: [:name, :title, :value, { csat_survey_response: [:feedback_message, :rating] }])
  end

  def permitted_params
    params.permit(:content, :echo_id, :source_id)
  end

  def set_message
    @message = @conversation.messages.find(params[:id])
  end

  def message_params
    base_message_params.then { |attributes| with_group_sender(attributes) }
  end

  def base_message_params
    {
      account_id: @conversation.account_id,
      sender: @contact_inbox.contact,
      content: permitted_params[:content],
      inbox_id: @conversation.inbox_id,
      echo_id: permitted_params[:echo_id],
      source_id: permitted_params[:source_id],
      message_type: :incoming
    }
  end

  # Em conversa de GRUPO o autor vem embutido no texto — a app `chatwoot` da WAHA
  # concatena nome + identificador no corpo porque o `sender` da mensagem e sempre
  # o contato-grupo. Aqui o texto volta a ser so o texto e o autor vira dado.
  #
  # `content_attributes` e montado por NOS a partir do proprio conteudo; nada vem
  # do cliente (`permitted_params` segue permitindo apenas content/echo_id/source_id).
  # Em 1:1 este metodo e no-op: devolve os atributos exatamente como recebeu.
  def with_group_sender(attributes)
    return attributes unless waha_multi_participant_chat?

    extracted = Whatsapp::GroupSenderExtractor.call(attributes[:content])
    return attributes unless extracted.matched?

    attributes[:content] = extracted.content
    attributes[:content_attributes] = { 'group_sender' => resolve_sender_phone(extracted.sender) } if extracted.sender?
    attributes
  rescue StandardError => e
    # Enriquecimento nunca pode derrubar a ingestao: na duvida, grava como antes.
    Rails.logger.warn("[GroupSender] extracao falhou (conversation=#{@conversation&.id}): #{e.class} #{e.message}")
    base_message_params
  end

  # Chat com mais de um participante possivel — e so nesses que a WAHA embute o
  # autor no texto. O gatilho e SEMPRE estrutural (o JID do chat), nunca o texto:
  # e isso que garante que uma conversa 1:1 de verdade nao muda em nada, mesmo que
  # alguem digite algo parecido com o prefixo.
  def waha_multi_participant_chat?
    @conversation&.group? || waha_broadcast_chat?
  end

  # `Conversation#group?` e o ponto unico de verdade sobre `@g.us` e nao deve ser
  # alargado (outros guards dependem dele). Broadcast fica so aqui, na ingestao.
  def waha_broadcast_chat?
    contact = @conversation&.contact
    return false if contact.blank?

    custom = contact.custom_attributes || {}
    custom.values_at('waha_whatsapp_chat_id', 'waha_whatsapp_jid')
          .any? { |jid| jid.to_s.end_with?(WHATSAPP_BROADCAST_JID_SUFFIX) }
  end

  # Acerto de cache: quando o telefone deste LID ja foi resolvido antes, ele entra
  # junto com a mensagem e nenhum job e enfileirado.
  def resolve_sender_phone(sender)
    return sender if sender['lid'].blank? || sender['phone'].present?

    phone = Whatsapp::LidPhoneCache.phone(group_waha_session_name, sender['lid'])
    phone.present? ? sender.merge('phone' => phone) : sender
  end

  def group_waha_session_name
    @conversation&.inbox&.waha_session_name
  end

  # Miss de cache: resolve fora do request. A WAHA pode estar lenta ou fora — a
  # mensagem ja esta gravada, o telefone chega depois (ou nunca).
  def schedule_group_sender_phone_resolution
    sender = @message&.content_attributes&.dig('group_sender')
    return if sender.blank? || sender['lid'].blank? || sender['phone'].present?

    Whatsapp::ResolveGroupSenderPhoneJob.perform_later(@message.id)
  rescue StandardError => e
    Rails.logger.warn("[GroupSender] falha ao enfileirar resolucao de telefone: #{e.class} #{e.message}")
  end

  def check_csat_locked
    (Time.zone.now.to_date - @message.created_at.to_date).to_i > 14 and @message.content_type == 'input_csat'
  end
end
