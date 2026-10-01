# Resumo FACTUAL da jornada de uma conversa: o que o contato pediu, o que aconteceu em ordem,
# quem atendeu (atendente com nome e time, ou IA) e o que ficou pendente (CHAT-180, parte 3).
#
# Serviço reutilizável: a reentrada da IA usa para substituir o histórico antigo, e a
# transferência entre caixas pode usar para mandar o resumo junto. Quem chama decide quando —
# este serviço não tem flag própria.
#
# Não consome a cota do Captain (o retorno não é Hash com :message, que é o que
# Enterprise::Captain::BaseTaskService cobra) e prefere a chave de sistema, como o
# ConversationCompletionService: é contexto interno, não resposta ao cliente.
class Captain::Conversation::JourneySummary < Captain::BaseTaskService
  # O passado relevante cabe aqui; ir além só encarece a chamada.
  LIMITE_MENSAGENS = 300
  LIMITE_CARACTERES = 40_000
  CACHE_TTL = 30.days
  IA_SENDERS = %w[Captain::Assistant AgentBot].freeze

  pattr_initialize [:account!, :conversation_display_id!, :ate]

  # String com o resumo, ou nil quando não há mensagem ou a geração falha. Nunca levanta.
  def self.for(conversation, ate: nil)
    new(account: conversation.account, conversation_display_id: conversation.display_id, ate: ate).perform
  end

  # Uma linha da transcrição, com data e origem. Pública porque a ferramenta de consulta ao
  # histórico devolve os trechos no mesmo formato.
  def self.linha(message)
    quando = message.created_at.in_time_zone(Time.zone).strftime('%d/%m/%Y %H:%M')
    "#{quando} · #{origem(message)}: #{message.content_for_llm.to_s.gsub(/\s+/, ' ').strip}"
  end

  def self.origem(message)
    return 'contato' if message.incoming?
    return "IA #{message.sender.try(:name)}".strip if IA_SENDERS.include?(message.sender_type)
    return 'mensagem automática' unless message.sender_type == 'User'

    nome = message.sender.try(:available_name).to_s.strip.presence || 'sem nome'
    time = message.conversation.team&.name.to_s.strip
    time.present? ? "atendente #{nome} (time #{time})" : "atendente #{nome}"
  end

  def perform
    mensagens = selecionadas
    return if mensagens.empty?

    Rails.cache.fetch(chave(mensagens.last.id), expires_in: CACHE_TTL, skip_nil: true) { gerar(mensagens) }
  rescue StandardError => e
    Rails.logger.warn("[JourneySummary] conv=#{conversation_display_id}: #{e.class}: #{e.message}")
    nil
  end

  private

  def selecionadas
    escopo = conversation.messages.where(message_type: %i[incoming outgoing], private: false)
    escopo = escopo.where('messages.id <= ?', ate) if ate.present?
    escopo.includes(:sender).reorder(id: :desc).limit(LIMITE_MENSAGENS).to_a.reverse
  end

  # Corta do mais ANTIGO para caber no limite: o fim da jornada é o que o leitor mais precisa.
  def transcricao(mensagens)
    linhas = mensagens.map { |m| self.class.linha(m) }
    linhas.shift while linhas.sum(&:length) > LIMITE_CARACTERES && linhas.size > 1
    linhas.join("\n")
  end

  def gerar(mensagens)
    resposta = make_api_call(
      model: InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || GPT_MODEL,
      messages: [
        { role: 'system', content: Rails.root.join('enterprise/lib/captain/prompts/journey_summary.liquid').read },
        { role: 'user', content: transcricao(mensagens) }
      ]
    )
    return if resposta[:error].present?

    resposta[:message].to_s.strip.presence
  end

  # A chave inclui a última mensagem resumida: o mesmo trecho não gera dois resumos, e trecho
  # maior (conversa que andou) gera um novo.
  def chave(ultimo_id)
    "captain:journey_summary:v1:#{conversation.id}:#{ultimo_id}"
  end

  # Gate é de quem chama (reentrada por flag de conta; transferência pela regra dela).
  def captain_tasks_enabled?
    true
  end

  def api_key
    @api_key ||= system_api_key.presence || openai_hook&.settings&.dig('api_key')
  end

  def event_name
    'captain.journey_summary'
  end

  def build_follow_up_context?
    false
  end
end
