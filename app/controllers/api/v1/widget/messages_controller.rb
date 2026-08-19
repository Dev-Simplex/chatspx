class Api::V1::Widget::MessagesController < Api::V1::Widget::BaseController
  # 4.01 — tipos de mensagem ESTRUTURADA cuja resposta do visitante vira mensagem `incoming`.
  # `input_email` fica de fora de propósito: ele já tem caminho próprio (ContactIdentifyAction) e
  # não é uma resposta de conversa.
  FLOW_REPLY_CONTENT_TYPES = %w[input_select form].freeze

  before_action :set_conversation, only: [:create]
  before_action :set_message, only: [:update]

  def index
    @messages = conversation.nil? ? [] : message_finder.perform
  end

  def create
    @message = conversation.messages.new(message_params)
    build_attachment
    @message.save!
  end

  def update
    if @message.content_type == 'input_email'
      @message.update!(submitted_email: contact_email)
      # PORTA 4 (bloco 4.16): mesma historia do pre-chat. O e-mail digitado fica gravado em
      # `submitted_email` de qualquer forma, entao recusar o merge nao perde o dado — o
      # agente continua vendo o que o visitante escreveu.
      ContactIdentifyAction.new(
        contact: @contact,
        params: { email: contact_email, name: contact_name },
        retain_original_contact_name: true,
        identity_enforcement: conversation&.inbox&.resolved_identity_enforcement
      ).perform
    else
      # Lido ANTES do update: depois dele `submitted_values` sempre existe, e a idempotência
      # ("2 cliques = 1 mensagem") precisa saber se ESTA requisição foi a primeira resposta.
      already_answered = submitted_values.present?
      @message.update!(message_update_params[:message])
      echo_visitor_reply unless already_answered
    end
  rescue StandardError => e
    render json: { error: @contact.errors, message: e.message }.to_json, status: :internal_server_error
  end

  private

  # 4.01 — A PONTE QUE FALTAVA no canal web.
  #
  # Responder a uma mensagem estruturada no widget gravava `submitted_values` na PRÓPRIA mensagem
  # outgoing e parava aí: nenhuma mensagem `incoming` nascia. Como o AutomationRuleListener só
  # olha `message_created` de mensagem incoming (#resume_pending_reply → Flows::ReplyResumeService),
  # um Flow com `wait_for_reply` NUNCA retomava no widget — o FlowRun ficava `waiting` para sempre.
  #
  # Aqui a resposta do visitante vira mensagem de verdade, no MESMO formato que o WhatsApp já
  # persiste (`content_attributes.selected_option`, Whatsapp::IncomingMessageBaseService#message_content_attributes):
  # é esse hash que o wait_for_reply consome como branch — id da opção == `value` do item do
  # send_interactive == `edge.branch`.
  #
  # Duas guardas fecham o aceite do bloco:
  #  · motor DESLIGADO ⇒ nada muda (nenhuma mensagem nasce; transcrição idêntica à de hoje);
  #  · 2 cliques ⇒ 1 mensagem e 1 retomada (o 2º clique já encontra `submitted_values` gravado).
  def echo_visitor_reply
    return unless FLOW_REPLY_CONTENT_TYPES.include?(@message.content_type)
    return unless flows_engine_active?

    content = visitor_reply_content
    return if content.blank?

    reply = @message.conversation.messages.create!(
      account_id: @message.account_id,
      inbox_id: @message.inbox_id,
      message_type: :incoming,
      sender: @contact,
      content: content,
      content_attributes: visitor_reply_content_attributes
    )
    mark_replied(reply)
  end

  # Mesmo gate do AutomationRuleListener#flows_engine_active?: a flag da conta E existir flow ativo.
  # A flag sozinha (ligada antes do backfill) faria a mensagem nova cair no motor ANTIGO de
  # AutomationRules, disparando regra que hoje não dispara — regressão silenciosa.
  def flows_engine_active?
    account = @message.account
    account.present? && account.flows_engine_enabled? && account.flows.active.exists?
  end

  # Marca a mensagem estruturada com o id da resposta materializada. É o que o widget lê para NÃO
  # desenhar o balão local duplicado (a mensagem real chega pela lista e se desenha sozinha) — ver
  # AgentMessage.vue#hasRecordedResponse. Sem motor, a chave nunca existe e o widget é o de hoje.
  def mark_replied(reply)
    @message.update!(content_attributes: @message.content_attributes.merge('reply_message_id' => reply.id))
  end

  def submitted_values
    Array(@message.content_attributes['submitted_values']).grep(Hash)
  end

  # O texto da resposta: numa lista de opções é o rótulo escolhido; num formulário são os pares
  # `campo: valor`, uma linha cada, na ordem em que o visitante preencheu.
  def visitor_reply_content
    values = submitted_values
    return if values.blank?

    return option_label(values.first) if @message.input_select?

    values.filter_map { |value| form_field_line(value) }.join("\n")
  end

  def option_label(option)
    (option['title'].presence || option['value']).to_s
  end

  def form_field_line(value)
    filled = value['value'].to_s.strip
    return if filled.blank?

    label = value['name'].presence || value['title']
    label.present? ? "#{label}: #{filled}" : filled
  end

  # `selected_option` só existe quando houve ESCOLHA de opção — é o par {id, title} que o
  # wait_for_reply casa contra `edge.branch`. Num formulário não há opção: o casamento cai no
  # conteúdo (AutomationRuleListener#reply_from_message já faz esse fallback).
  def visitor_reply_content_attributes
    attrs = { 'in_reply_to' => @message.id }
    option = submitted_values.first
    return attrs unless @message.input_select? && option.present?

    attrs.merge('selected_option' => { 'id' => (option['value'].presence || option['title']).to_s,
                                       'title' => option_label(option) })
  end

  def build_attachment
    return if params[:message][:attachments].blank?

    params[:message][:attachments].each do |uploaded_attachment|
      attachment = @message.attachments.new(
        account_id: @message.account_id,
        file: uploaded_attachment
      )

      attachment.file_type = helpers.file_type(uploaded_attachment&.content_type) if uploaded_attachment.is_a?(ActionDispatch::Http::UploadedFile)
    end
  end

  def set_conversation
    return unless conversation.nil?

    @conversation = create_conversation
    apply_labels if permitted_params[:labels].present?
  end

  def apply_labels
    valid_labels = inbox.account.labels.where(title: permitted_params[:labels]).pluck(:title)
    @conversation.update_labels(valid_labels) if valid_labels.present?
  end

  def message_finder_params
    {
      filter_internal_messages: true,
      before: permitted_params[:before],
      after: permitted_params[:after]
    }
  end

  def message_finder
    @message_finder ||= MessageFinder.new(conversation, message_finder_params)
  end

  def message_update_params
    params.permit(message: [{ submitted_values: [:name, :title, :value, { csat_survey_response: [:feedback_message, :rating] }] }])
  end

  def permitted_params
    # timestamp parameter is used in create conversation method
    # custom_attributes and labels are applied when a new conversation is created alongside the first message
    params.permit(
      :id, :before, :after, :website_token,
      contact: [:name, :email],
      message: [:content, :referer_url, :timestamp, :echo_id, :reply_to],
      custom_attributes: {},
      labels: []
    )
  end

  def set_message
    # `conversation.messages.find` would be simpler, but `conversation` is `conversations.last`,
    # which means a visitor with more than one open thread could not edit a message in any
    # but their most recent one. Scoping across all of the visitor's conversations keeps the
    # happy path correct for that future multi-conversation widget flow.
    @message = Message.where(conversation_id: conversations.select(:id)).find(permitted_params[:id])
  end
end
