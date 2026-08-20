# Fronteira do atendimento ATUAL, disponível no instante do turno.
#
# A tabela `captain_conversation_episodes` é populada por CRON, então depender dela deixa o
# runtime sem fronteira justamente no primeiro turno de uma reentrada — que é onde o dano
# acontece. Medido na conv 20215: cliente escreveu 09:40:07, a IA respondeu 09:41:55 e os
# três episódios só nasceram às 10:07:17. No instante do turno não havia linha nenhuma.
#
# Por isso a ordem é: usa a tabela SE ela já cobre a última mensagem (atalho barato), senão
# DERIVA na hora com o mesmo cálculo do EpisodeSegmenterService (resolve · HSM · gap da
# conta). Reusa o serviço em vez de reimplementar: duas cópias da regra divergem, e aí a
# janela do runtime deixaria de bater com o episódio que o eval julga.
class Captain::Conversation::EpisodeBoundary
  # Só o que o runtime e a nota precisam — vem tanto da tabela quanto da derivação.
  Atendimento = Struct.new(:seq, :started_at, :ended_at, :boundary_reason,
                           :first_message_id, :last_message_id, keyword_init: true)

  SEGMENTAVEIS = %i[incoming outgoing activity template].freeze

  def initialize(conversation:)
    @conversation = conversation
  end

  # Atendimento em andamento. nil só quando não há mensagem segmentável nenhuma.
  def atual
    lista.last
  end

  # Encerrados, do mais recente pro mais antigo.
  def anteriores(limite:)
    return [] if lista.size <= 1

    lista[0..-2].last(limite).reverse
  end

  def total_anteriores
    [lista.size - 1, 0].max
  end

  private

  def lista
    @lista ||= com_conversa(da_tabela || derivados)
  end

  # Descarta "atendimentos" formados só por `activity` e renumera.
  #
  # ⚠️ CONTORNO de um defeito do EpisodeSegmenterService, não capricho: o `next if
  # row[:type] == 2` dele nunca casa, porque `pluck` de coluna enum devolve o RÓTULO
  # ("activity"), não o inteiro — verificado em prod. Com isso a activity de encerramento
  # ("Conversation was resolved by…") vira mensagem conversacional e chega a ABRIR
  # episódio. Medido na conta 6: 97 das 183 reentradas de uma amostra de 250 abriam numa
  # activity e ficavam com janela vazia.
  #
  # O defeito é do segmentador e atinge também os episódios que o eval julga; corrigir lá
  # re-segmenta as ~14.9k linhas existentes e quebra a comparabilidade do histórico do
  # eval, então é decisão à parte. Aqui só se garante que a janela do runtime não nasça
  # de um marcador de sistema.
  def com_conversa(atendimentos)
    return atendimentos if atendimentos.blank?

    ids = @conversation.messages.where(message_type: %i[incoming outgoing]).where(private: false).pluck(:id)
    return atendimentos if ids.empty?

    atendimentos.select { |a| ids.any? { |id| id.between?(a.first_message_id.to_i, a.last_message_id.to_i) } }
                .each_with_index.map { |a, indice| a.tap { a.seq = indice + 1 } }
  end

  # Atalho: a tabela serve quando o último episódio já alcança a última mensagem
  # segmentável. Defasada, é pior que inútil — apontaria uma fronteira velha.
  def da_tabela
    ultima = @conversation.messages.where(message_type: SEGMENTAVEIS).where(private: false).maximum(:id)
    return if ultima.nil?

    episodios = Captain::ConversationEpisode.where(conversation_id: @conversation.id).order(:seq).to_a
    return if episodios.empty? || episodios.last.last_message_id.to_i < ultima

    episodios.map { |episodio| do_episodio(episodio) }
  rescue StandardError => e
    Rails.logger.warn("[EpisodeBoundary] tabela conv=#{@conversation.id}: #{e.class}: #{e.message}")
    nil
  end

  def do_episodio(episodio)
    Atendimento.new(seq: episodio.seq, started_at: episodio.started_at, ended_at: episodio.ended_at,
                    boundary_reason: episodio.boundary_reason,
                    first_message_id: episodio.first_message_id, last_message_id: episodio.last_message_id)
  end

  def derivados
    Captain::EpisodeSegmenterService.new(conversation: @conversation).preview.each_with_index.map do |segmento, indice|
      Atendimento.new(seq: indice + 1, started_at: segmento.started_at,
                      # 'aberto' é o único reason que significa "ainda em andamento"
                      ended_at: segmento.reason == 'aberto' ? nil : segmento.last_at,
                      boundary_reason: segmento.reason,
                      first_message_id: segmento.first_id, last_message_id: segmento.last_id)
    end
  rescue StandardError => e
    Rails.logger.warn("[EpisodeBoundary] derivação conv=#{@conversation.id}: #{e.class}: #{e.message}")
    []
  end
end
