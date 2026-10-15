# Envia o pin de localizacao do escritorio da conta pelo pipeline NATIVO do SPX:
# uma mensagem outgoing com anexo file_type :location -> WhatsappCloudService#send_location_message.
class Captain::Tools::EnviarLocalizacaoTool < Captain::Tools::BasePublicTool
  description 'Envia ao cliente a localização (pin no mapa) do escritório da empresa pelo WhatsApp. ' \
              'Chame quando o cliente perguntar onde fica a empresa, pedir o endereço, a localização ou como chegar.'

  def perform(tool_context)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa pra enviar a localização.' unless conversation

    # Coordenadas do escritório por CONTA via concern (AccountIntegration vista office_*). Sem
    # elas não há pin: nenhuma mensagem sai, e o modelo é avisado para não inventar endereço.
    office = office_coords
    return 'O endereço do escritório não está configurado nesta conta: nenhum pin foi enviado. Não invente endereço.' unless office

    # Anexo construido ANTES do save (o envio dispara no after_create_commit; create
    # em duas etapas seria corrida — mesmo cuidado da EnviarFotosImovelTool).
    msg = conversation.messages.build(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: @assistant
    )
    msg.attachments.build(
      account_id: conversation.account_id,
      file_type: :location,
      coordinates_lat: office[:lat],
      coordinates_long: office[:lng],
      fallback_title: office[:name]
    )
    msg.save!
    log_tool_usage('enviar_localizacao', conversation_id: conversation.id)
    'Pin de localização do escritório enviado ao cliente. Confirme com naturalidade e siga a conversa.'
  rescue StandardError => e
    Rails.logger.warn("[EnviarLocalizacaoTool] #{e.message}")
    'Não consegui enviar a localização agora.'
  end
end
