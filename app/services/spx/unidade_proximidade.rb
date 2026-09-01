# "Qual a mais perto de mim" — a parte geográfica da consulta de unidades, fora da ferramenta.
#
# Existe separada por dois motivos: a BuscarUnidadesTool já é a maior classe do módulo, e esta
# conta vale para qualquer chamador (a tela, um relatório, outra tool) sem arrastar o toolset.
#
# O PONTO DA PESSOA vem do pin que ela enviou na conversa, e de mais lugar nenhum. Não há
# geocoding aqui de propósito: a conta da BigStore não tem integração google, e o geocoding do
# Google não avisa quando erra — devolve homônimo (medido na Tozi: 67 de 259 bairros a mais de
# 3 km, um a 518 km). Sem pin, esta classe simplesmente não fala de distância.
class Spx::UnidadeProximidade
  def self.ponto_da_conversa(conversation)
    return nil unless conversation

    anexo = ::Attachment.joins(:message)
                        .where(messages: { conversation_id: conversation.id, message_type: :incoming })
                        .where(file_type: :location)
                        .where.not(coordinates_lat: nil).where.not(coordinates_long: nil)
                        .order(id: :desc).first
    return nil unless anexo

    [anexo.coordinates_lat, anexo.coordinates_long]
  rescue StandardError => e
    Rails.logger.warn("[UnidadeProximidade] ponto da conversa indisponível: #{e.class} #{e.message}")
    nil
  end

  # Abaixo de 10 km a casa decimal muda a decisão de quem está na cidade; acima dela, só polui.
  def self.km(distancia)
    return nil unless distancia

    distancia < 10 ? format('~%.1f km', distancia) : "~#{distancia.round} km"
  end

  def initialize(ponto)
    @ponto = ponto
  end

  def ativa?
    @ponto.present?
  end

  def distancia(unidade)
    return nil unless ativa?

    unidade.distancia_de(*@ponto)
  end

  # Unidade SEM coordenada vai para o fim, nunca para o começo: distância desconhecida tratada
  # como zero colocaria a loja errada como "a mais perto", que é a única resposta que não pode
  # sair daqui. O nome desempata para a ordem ser estável entre chamadas.
  def ordenar(unidades)
    return unidades unless ativa?

    unidades.sort_by { |unidade| [distancia(unidade) || Float::INFINITY, unidade.nome.to_s] }
  end

  def mais_proxima(unidades)
    return nil unless ativa?

    unidades.select(&:coordenada?).min_by { |unidade| distancia(unidade) }
  end
end
