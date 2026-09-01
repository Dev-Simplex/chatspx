# Busca na Graph o que o webhook do comentário não traz: legenda, permalink, miniatura e as
# contagens públicas.
#
# BEST-EFFORT DE PROPÓSITO. Quem chama já gravou o comentário; aqui só se acrescenta contexto.
# Falha vira log com o corpo da resposta e nada mais — mas o log é obrigatório, porque a Meta
# devolve HTTP 200 com o campo simplesmente AUSENTE quando falta permissão, e sem registro
# ninguém descobriria por que a legenda nunca aparece.
class Spx::Social::InstagramPublicacaoSync
  # Uma publicação viral traz dezenas de comentários em minutos, e cada um pediria a mesma
  # legenda. Legenda não muda; contagem muda devagar. Seis horas é o suficiente pra tela não
  # mentir e a API não apanhar.
  JANELA_DE_RESINCRONIA = 6.hours

  CAMPOS = %w[
    caption permalink media_type media_product_type media_url thumbnail_url
    timestamp like_count comments_count
  ].freeze

  pattr_initialize [:publicacao!, :channel!]

  def perform
    return if recente?

    dados = buscar
    return if dados.blank?

    gravar(dados)
  end

  private

  # O rescue de `buscar` cobria só a conversa com a Meta, e a gravação ficava de fora — então
  # uma linha que o banco recusa derrubava quem chamou. Isso não é teórico: `thumbnail_url` era
  # `string(255)`, a URL do CDN passa disso, e a exceção subia pela captura do comentário e
  # **matava o gatilho da IA**. A coluna virou `text`, mas o contrato deste serviço é
  # best-effort e agora ele cumpre: nada aqui pode derrubar a captura.
  def gravar(dados)
    publicacao.update!(atributos(dados))
  rescue StandardError => e
    Rails.logger.error("[social] falha ao gravar publicacao #{publicacao.external_id}: #{e.class} #{e.message}")
    ChatwootExceptionTracker.new(e, account: publicacao.account).capture_exception
    nil
  end

  def recente?
    publicacao.sincronizada_em.present? && publicacao.sincronizada_em > JANELA_DE_RESINCRONIA.ago
  end

  def atributos(dados)
    {
      legenda: dados['caption'],
      permalink: dados['permalink'],
      tipo: dados['media_product_type'].presence || publicacao.tipo,
      thumbnail_url: dados['thumbnail_url'].presence || dados['media_url'],
      publicada_em: parse_timestamp(dados['timestamp']),
      metricas: publicacao.metricas.merge(
        'like_count' => dados['like_count'],
        'comments_count' => dados['comments_count']
      ).compact,
      sincronizada_em: Time.current
    }
  end

  def buscar
    resposta = requisitar
    return resposta.parsed_response if resposta.success? && resposta.parsed_response.is_a?(Hash)

    Rails.logger.error("[social] falha ao sincronizar publicacao #{publicacao.external_id}: HTTP #{resposta.code}")
    nil
  rescue StandardError => e
    Rails.logger.error("[social] erro ao sincronizar publicacao #{publicacao.external_id}: #{e.message}")
    ChatwootExceptionTracker.new(e, account: publicacao.account).capture_exception
    nil
  end

  def requisitar
    HTTParty.get(
      "#{base_uri}/#{publicacao.external_id}",
      query: { fields: CAMPOS.join(','), access_token: channel.access_token },
      headers: { 'Accept' => 'application/json' }
    )
  end

  def parse_timestamp(valor)
    return if valor.blank?

    Time.zone.parse(valor)
  rescue ArgumentError
    nil
  end

  def base_uri
    "https://graph.instagram.com/#{GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0')}"
  end
end
