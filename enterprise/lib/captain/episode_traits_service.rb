# Calcula os TRAÇOS DE CONDUTA de um episódio (Eval 2.0 F3): como o atendimento foi
# conduzido, em números. Custo zero — conta mensagens, não chama LLM.
#
# É a outra metade da correlação. O desfecho (Captain::EpisodeOutcomeService) diz O QUE
# aconteceu; o traço diz COMO foi conduzido. Um sem o outro não responde a pergunta que
# originou o F3 — só os dois, cruzados e segmentados por campanha.
#
# Idempotente: recalcula por cima. Traço de episódio FECHADO é estável (episódio fechado
# é imutável); episódio aberto tem traço parcial, que se corrige na próxima passada.
class Captain::EpisodeTraitsService
  # Quem conta como "a IA falando". AgentBot cobre o espelho do assistant.
  IA_SENDERS = %w[Captain::Assistant AgentBot].freeze
  TOOL_WINDOW = 3.minutes
  # Ver #ferramentas: as tools que detectam degrau não podem contar como conduta.
  TOOLS_DETECTORAS = %w[salvar_info_lead handoff transferir_para_agente].freeze

  pattr_initialize [:episode!]

  def perform
    return unless Captain::ConversationEval.enabled_for?(episode.account)

    episode.update!(**traits)
    episode
  rescue StandardError => e
    Rails.logger.warn("[eval-traits] episódio #{episode.id}: #{e.class} #{e.message}")
    nil
  end

  private

  def conversation
    @conversation ||= episode.conversation
  end

  def fim
    @fim ||= episode.ended_at || episode.last_message_at
  end

  # includes(:attachments) evita N+1 no enviou_midia — o backfill roda sobre milhares
  # de episódios de uma vez.
  def mensagens
    @mensagens ||= conversation.messages
                               .where(id: episode.first_message_id..episode.last_message_id)
                               .where(private: false)
                               .includes(:attachments)
                               .reorder(:created_at)
                               .to_a
  end

  def respostas_ia
    @respostas_ia ||= mensagens.select { |m| m.outgoing? && IA_SENDERS.include?(m.sender_type) }
  end

  def traits
    {
      turnos_ia: respostas_ia.size,
      turnos_cliente: mensagens.count(&:incoming?),
      chars_resposta_media: chars_media,
      ferramentas_usadas: ferramentas,
      enviou_midia: respostas_ia.any? { |m| m.attachments.any? },
      duracao_segundos: duracao,
      campanha: conversation.custom_attributes&.dig('meta_campanha')
    }
  end

  # Só mensagens com texto entram na média: bolha de mídia pura tem content vazio e
  # puxaria a média pra baixo sem que ninguém tivesse escrito mais curto.
  def chars_media
    tamanhos = respostas_ia.filter_map do |m|
      tamanho = m.content.to_s.strip.length
      tamanho.positive? ? tamanho : nil
    end
    return if tamanhos.empty?

    (tamanhos.sum.to_f / tamanhos.size).round
  end

  # Só ferramentas de CONTEÚDO (busca, fotos, localização). As que DEFINEM degraus
  # ficam de fora: `qualificado` é detectado por salvar_info_lead, então contá-la como
  # conduta tornaria a métrica circular — "quem converteu usou mais tools" seria o
  # detector se medindo, não um traço de conduta.
  def ferramentas
    Captain::ToolCall.for_conversation(conversation.id)
                     .in_window(episode.started_at, fim + TOOL_WINDOW)
                     .where.not(tool_name: TOOLS_DETECTORAS)
                     .count
  end

  def duracao
    return if fim.blank? || episode.started_at.blank?

    (fim - episode.started_at).round
  end
end
