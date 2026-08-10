class Captain::Tools::AtualizarResumoTool < Captain::Tools::BasePublicTool
  description 'Cria ou atualiza o RESUMO do atendimento da IA na conversa (atributo "Resumo Atendimento IA"). ' \
              'Chame quando você entender bem o assunto e qualificar com qualidade (em geral no momento do handoff) ' \
              'e, depois, sempre que surgir informação importante que mude ou complemente o resumo. Você decide ' \
              'quando vale — não a cada mensagem, só quando há algo relevante novo. Sobrescreve o resumo anterior.'

  param :resumo, type: 'string',
                 desc: 'O resumo atual e completo do atendimento: o que o cliente quer, o que foi qualificado, status, ' \
                       'próximos passos e outros assuntos pendentes. Escreva o quadro corrente inteiro (não só o delta).',
                 required: true

  def perform(tool_context, resumo:)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa pra atualizar o resumo.' unless conversation
    return 'Resumo vazio, nada a salvar.' if resumo.to_s.strip.empty?

    sanitized_summary = Captain::Tools::SensitiveDataSanitizer.sanitize(resumo.to_s).strip
    attrs = conversation.custom_attributes.to_h
    attrs['resumo_atendimento_ia'] = sanitized_summary
    conversation.update!(custom_attributes: attrs)
    'Resumo do atendimento atualizado.'
  rescue StandardError => e
    Rails.logger.warn("[AtualizarResumoTool] #{e.message}")
    'Não consegui atualizar o resumo agora.'
  end
end
