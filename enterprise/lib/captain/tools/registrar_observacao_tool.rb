class Captain::Tools::RegistrarObservacaoTool < Captain::Tools::BasePublicTool
  description 'Registra uma OBSERVAÇÃO como nota privada na conversa (visível só pra equipe, nunca pro cliente). ' \
              'NÃO é resumo — é pra sinalizar algo importante que o humano deve notar ao ler o histórico. ' \
              'Ex.: o cliente é o fiador e não o inquilino; cliente irritado ou com pressa; já reclamou antes; ' \
              'tem FGTS pra resgatar; restrição no nome. Chame quando julgar que há algo relevante a ressaltar; ' \
              'pode ser curta ou detalhada, conforme a necessidade.'

  param :observacao, type: 'string',
                     desc: 'A observação a registrar como nota privada, pro humano notar ao ler o histórico da conversa.',
                     required: true

  def perform(tool_context, observacao:)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa pra registrar a observação.' unless conversation
    return 'Observação vazia, nada a registrar.' if observacao.to_s.strip.empty?

    conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      sender: @assistant,
      account: conversation.account,
      inbox: conversation.inbox,
      content: observacao.to_s.strip
    )
    'Observação registrada.'
  rescue StandardError => e
    Rails.logger.warn("[RegistrarObservacaoTool] #{e.message}")
    'Não consegui registrar a observação agora.'
  end
end
