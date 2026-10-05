# Fronteira do atendimento ATUAL, disponível no instante do turno.
#
# A tabela `captain_conversation_episodes` é populada por CRON, então depender dela deixa o
# runtime sem fronteira justamente no primeiro turno de uma reentrada — que é onde o dano
# acontece. Medido na conv 20215: cliente escreveu 09:40:07, a IA respondeu 09:41:55 e os
# três episódios só nasceram às 10:07:17. No instante do turno não havia linha nenhuma.
#
# Por isso a fronteira é DERIVADA na hora pelo EpisodeSegmenterService#preview (resolve · HSM
# · gap da conta). Reusa o serviço em vez de reimplementar a regra.
#
# A tabela não serve nem de atalho: o cron grava a segmentação do Eval, que ignora a resolução
# e o template (ver EpisodeSegmenterService#tipo?). Com o atalho, a janela voltaria a juntar o
# atendimento resolvido de véspera assim que o cron passasse (CHAT-180). Por decisão do Paulo
# (01/10/2026) as duas segmentações divergem: a janela do runtime não bate com o episódio que
# o Eval julga.
class Captain::Conversation::EpisodeBoundary
  # Só o que o runtime e a nota precisam.
  Atendimento = Struct.new(:seq, :started_at, :ended_at, :boundary_reason,
                           :first_message_id, :last_message_id, keyword_init: true)

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
    @lista ||= com_conversa(derivados)
  end

  # Descarta "atendimentos" formados só por `activity` e renumera.
  #
  # Nasceu como contorno do defeito de enum do segmentador, que fazia a activity de
  # encerramento ABRIR episódio (medido na conta 6: 97 das 183 reentradas de uma amostra de
  # 250 abriam numa activity e ficavam com janela vazia). O #preview já não faz isso; o filtro
  # fica como garantia de que a janela nunca nasce de um marcador de sistema.
  def com_conversa(atendimentos)
    return atendimentos if atendimentos.blank?

    ids = @conversation.messages.where(message_type: %i[incoming outgoing]).where(private: false).pluck(:id)
    return atendimentos if ids.empty?

    atendimentos.select { |a| ids.any? { |id| id.between?(a.first_message_id.to_i, a.last_message_id.to_i) } }
                .each_with_index.map { |a, indice| a.tap { a.seq = indice + 1 } }
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
