class Captain::Tools::SalvarInfoLeadTool < Captain::Tools::BasePublicTool
  description 'Salva informações do lead na conversa: status do lead e uma descrição curta sobre o cliente. ' \
              'Chame quando entender o perfil/situação do cliente, ou quando o lead esfriar e precisar de reabordagem futura. ' \
              'Atualiza o que já existir, sem apagar o resto.'

  param :status, type: 'string',
        desc: 'Status do lead: novo, em_contato, qualificado, esfriado, perdido ou convertido.', required: false
  param :sobre_cliente, type: 'string',
        desc: 'Descrição curta (1 a 2 frases) sobre o cliente: o que procura, perfil e situação.', required: false
  param :precisa_followup, type: 'boolean',
        desc: 'true quando a conversa precisa de reabordagem depois (cliente esfriou, pediu pra pensar, sem resposta).', required: false

  def perform(tool_context, status: nil, sobre_cliente: nil, precisa_followup: false)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa pra salvar as informações.' unless conversation

    attrs = conversation.custom_attributes.dup
    attrs['tozi_status_lead'] = status if status.present?
    attrs['sobre_cliente'] = sobre_cliente if sobre_cliente.present?
    conversation.update!(custom_attributes: attrs)

    mark_followup(conversation) if precisa_followup

    'Informações do lead salvas.'
  rescue StandardError => e
    Rails.logger.warn("[SalvarInfoLeadTool] #{e.message}")
    'Não consegui salvar as informações agora.'
  end

  private

  def mark_followup(conversation)
    conversation.add_labels((conversation.label_list + ['followup-ativo']).uniq)
  rescue StandardError => e
    Rails.logger.warn("[SalvarInfoLeadTool] label: #{e.message}")
  end
end
