class Captain::Tools::RegistrarAssuntoTool < Captain::Tools::BasePublicTool
  description 'Registra um ASSUNTO/tarefa identificado na conversa, que vira um item de checklist visível pra equipe. ' \
              'Chame quando o cliente trouxer mais de um assunto/pedido na mesma conversa (ex.: quer alugar uma casa ' \
              'e também vender outro imóvel): registre cada assunto ALÉM do principal, pra nada se perder no handoff. ' \
              'Uma chamada por assunto. Não duplica itens com o mesmo texto.'

  param :assunto, type: 'string',
                  desc: 'Um assunto ou tarefa curta e objetiva (ex.: "Vender apartamento no Centro", ' \
                        '"Dúvida sobre 2ª via de boleto"). Escreva só o assunto, sem explicação.',
                  required: true

  def perform(tool_context, assunto:)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa pra registrar o assunto.' unless conversation

    text = assunto.to_s.strip
    return 'Assunto vazio, nada a registrar.' if text.empty?

    attrs = conversation.custom_attributes.dup
    list = attrs['assuntos_checklist']
    list = [] unless list.is_a?(Array)
    return 'Esse assunto já está no checklist.' if list.any? { |i| i.is_a?(Hash) && i['text'].to_s.strip.casecmp?(text) }

    list << { 'id' => SecureRandom.uuid, 'text' => text, 'done' => false, 'source' => 'ia' }
    attrs['assuntos_checklist'] = list
    conversation.update!(custom_attributes: attrs)
    'Assunto registrado no checklist.'
  rescue StandardError => e
    Rails.logger.warn("[RegistrarAssuntoTool] #{e.message}")
    'Não consegui registrar o assunto agora.'
  end
end
