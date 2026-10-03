# Corte da REENTRADA: a IA assumiu uma conversa que já tinha história (CHAT-180, parte 3).
#
# Decisão do Paulo (01/10/2026): quando a IA assume uma conversa que já existia, tendo
# participado antes ou não, ela recebe o atendimento atual e um RESUMO do que aconteceu antes,
# não as mensagens antigas palavra por palavra. Caso que originou: conv 22777 (conta 6), em que
# a IA de triagem recebeu inteiro o atendimento de véspera de um humano e repetiu a autorização
# de entrada que ele tinha dado.
#
# O corte é a última mensagem de SAÍDA antes do momento em que a IA assumiu. O que o contato
# mandou depois dela — inclusive a mensagem que fez a conversa voltar para a IA — fica na janela:
# é o pedido que está esperando resposta.
class Captain::Conversation::Reentrada
  def self.enabled_for?(account)
    ActiveModel::Type::Boolean.new.cast(account&.custom_attributes&.dig('captain_reentry_summary')).present?
  end

  def initialize(conversation:)
    @conversation = conversation
  end

  # Id da última mensagem que fica FORA da janela da IA, ou nil quando não houve reentrada.
  def corte_id
    return @corte_id if defined?(@corte_id)

    @corte_id = calcular
  rescue StandardError => e
    Rails.logger.warn("[Reentrada] conv=#{@conversation.id}: #{e.class}: #{e.message}")
    @corte_id = nil
  end

  private

  def calcular
    assumiu_em = Captain::AssistantLog.where(conversation_id: @conversation.id, event_type: 'mirror_assigned').maximum(:created_at)
    return if assumiu_em.nil?

    @conversation.messages.where(message_type: :outgoing, private: false)
                 .where('messages.created_at < ?', assumiu_em)
                 .maximum(:id)
  end
end
