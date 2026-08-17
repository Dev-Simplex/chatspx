#######################################
# To create a whatsapp provider
# - Inherit this as the base class.
# - Implement `send_message` method in your child class.
# - Implement `send_template_message` method in your child class.
# - Implement `sync_templates` method in your child class.
# - Implement `validate_provider_config` method in your child class.
# - Use Childclass.new(whatsapp_channel: channel).perform.
######################################

class Whatsapp::Providers::BaseService
  pattr_initialize [:whatsapp_channel!]

  # Cap defensivo de linhas numa lista interativa: a Meta estoura acima de 10. A validação primária
  # é no Flows::ActionService#sanitize_interactive_items; aqui é a última linha de defesa do canal
  # (vale p/ Cloud e 360dialog, que compartilham este builder). Ver plano/F1-contrato-send-interactive.md.
  WHATSAPP_INTERACTIVE_LIST_LIMIT = 10

  def send_message(_phone_number, _message)
    raise 'Overwrite this method in child class'
  end

  def send_template(_phone_number, _template_info, _message)
    raise 'Overwrite this method in child class'
  end

  def sync_template
    raise 'Overwrite this method in child class'
  end

  def validate_provider_config
    raise 'Overwrite this method in child class'
  end

  # "Digitando..." pro cliente. No-op por padrao; provedores que suportam
  # (WhatsApp Cloud API) sobrescrevem. Nunca deve levantar — e best-effort de UX.
  def send_typing_indicator(_source_id, _show_typing = true)
    nil
  end

  def error_message
    raise 'Overwrite this method in child class'
  end

  def process_response(response, message)
    parsed_response = response.parsed_response
    if response.success? && parsed_response['error'].blank?
      parsed_response['messages'].first['id']
    else
      handle_error(response, message)
      nil
    end
  end

  def handle_error(response, message)
    Rails.logger.error response.body
    return if message.blank?

    # https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes/#sample-response
    error_message = error_message(response)
    return if error_message.blank?

    message.external_error = error_message
    message.status = :failed
    message.save!
  end

  # WhatsApp coexistence / username migration: a contact may become addressable only by a Business-Scoped
  # User ID (BSUID, e.g. "BR.123..."), with no phone number available. The Cloud API requires a BSUID to be
  # passed in the `recipient` field (with recipient_type: individual), NOT in `to`. Passing a BSUID in `to`
  # returns HTTP 200 with a message id but the message is silently dropped: the "CC." prefix is stripped and
  # the remainder is treated as a phone number (wa_id), which never resolves. Phone numbers keep using `to`.
  # See: https://developers.facebook.com/documentation/business-messaging/whatsapp/business-scoped-user-ids/
  def recipient_params(identifier)
    if identifier.to_s.match?(RegexHelper::WHATSAPP_BSUID_REGEX)
      { recipient_type: 'individual', recipient: identifier }
    else
      { to: identifier }
    end
  end

  def create_buttons(items)
    buttons = []
    items.each do |item|
      button = { :type => 'reply', 'reply' => { 'id' => item['value'], 'title' => item['title'] } }
      buttons << button
    end
    buttons
  end

  def create_rows(items)
    rows = []
    # Cap defensivo (a Meta rejeita >10 linhas). `first` é no-op quando há ≤10.
    items.first(WHATSAPP_INTERACTIVE_LIST_LIMIT).each do |item|
      row = { 'id' => item['value'], 'title' => item['title'] }
      # Linha de lista suporta descrição (o botão não) — só inclui quando presente, senão a Meta
      # recebe um campo vazio. Chaves-string casam com o content_attributes persistido (jsonb).
      row['description'] = item['description'] if item['description'].present?
      rows << row
    end
    rows
  end

  def create_payload(type, message_content, action)
    {
      'type': type,
      'body': {
        'text': message_content
      },
      'action': action
    }
  end

  def create_payload_based_on_items(message)
    if message.content_attributes['items'].length <= 3
      create_button_payload(message)
    else
      create_list_payload(message)
    end
  end

  def create_button_payload(message)
    buttons = create_buttons(message.content_attributes['items'])
    json_hash = { 'buttons' => buttons }
    create_payload('button', message.outgoing_content, JSON.generate(json_hash))
  end

  def create_list_payload(message)
    rows = create_rows(message.content_attributes['items'])
    section1 = { 'rows' => rows }
    sections = [section1]
    json_hash = { :button => I18n.t('conversations.messages.whatsapp.list_button_label'), 'sections' => sections }
    create_payload('list', message.outgoing_content, JSON.generate(json_hash))
  end

  # Prefixa o conteudo com o nome do agente ("*Nome*:\n...") quando a inbox tem a
  # assinatura ligada (additional_attributes['agent_signature_enabled']). So p/ mensagem
  # de agente (User); midia sem legenda (content vazio) fica sem nome (Opcao B). Espelha o
  # formato que o bridge do WAHA ja aplica, mas so nos providers nativos (Cloud/360dialog).
  # Reintroduzido apos a reescrita do canvas interativo (40239f7571) ter removido isto.
  def with_agent_prefix(message, content)
    return content if content.blank?
    return content unless agent_signature_enabled?(message.inbox)
    return content unless message.sender_type == 'User' && message.sender.present?

    name = message.sender.available_name.to_s.strip
    name.present? ? "*#{name}*:\n#{content}" : content
  end

  # Toggle por inbox (default OFF). Ligado via additional_attributes['agent_signature_enabled'].
  def agent_signature_enabled?(inbox)
    inbox&.additional_attributes&.dig('agent_signature_enabled') == true
  end
end
