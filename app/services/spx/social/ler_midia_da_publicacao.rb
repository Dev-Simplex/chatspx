# frozen_string_literal: true

# Lê o que está escrito nas imagens de uma publicação e guarda como texto.
#
# O caso que motivou, medido ao vivo em 26/08: pergunta de preço num post de liquidação. A IA
# respondeu "consulte no direct" porque só tinha a legenda — e o preço estava nas imagens do
# carrossel, na frente de quem perguntou.
#
# Carrossel do Instagram vai até 20 itens, e o encarte espalha produto e preço entre eles: ler
# só o primeiro responderia errado com cara de certo. Por isso o teto é o do próprio formato, e
# uma leitura por item, em vez de empilhar tudo numa chamada só — o que economizaria chamadas e
# perderia justamente o detalhe que interessa, que é qual preço é de qual produto.
#
# Opt-in por conta (`social_reply['ler_midia']`): conta que não ligar não paga visão nenhuma.
class Spx::Social::LerMidiaDaPublicacao
  MAX_ITENS = 20
  JANELA = 24.hours

  pattr_initialize [:publicacao!]

  def perform
    return :desligada unless ligada?
    return :recente if recente?

    itens = midias
    return :sem_midia if itens.empty?

    textos = ler(itens)
    publicacao.update!(leitura_midia: textos.presence&.join("\n"), lida_em: Time.current)
    textos.empty? ? :sem_texto : :lida
  rescue StandardError => e
    Rails.logger.error("[social] leitura da publicacao #{publicacao.external_id} falhou: #{e.class} #{e.message}")
    :erro
  end

  private

  def ler(itens)
    itens.first(MAX_ITENS).each_with_index.filter_map do |item, i|
      texto = Spx::Social::LeitorDeMidia.new(url: item['media_url'], tipo: item['media_type'],
                                             account: publicacao.account).perform
      next if texto.blank? || texto.match?(/\Asem texto leg/i)

      itens.size > 1 ? "[imagem #{i + 1}] #{texto}" : texto
    end
  end

  # Uma publicação com mais itens que o teto perde os últimos. Isso NÃO pode ser silencioso: um
  # encarte truncado responde errado com cara de completo, e quem opera precisa saber que a
  # leitura não cobriu tudo.
  def midias
    itens = buscar_filhos
    Rails.logger.warn("[social] publicacao #{publicacao.external_id} tem #{itens.size} itens; lendo #{MAX_ITENS}") if itens.size > MAX_ITENS
    itens
  end

  def buscar_filhos
    dados = graph(publicacao.external_id, 'media_type,media_url')
    return [] if dados.blank?

    return [dados] unless dados['media_type'].to_s == 'CAROUSEL_ALBUM'

    filhos = graph("#{publicacao.external_id}/children", 'id,media_type,media_url')
    Array(filhos && filhos['data'])
  end

  def graph(caminho, campos)
    resposta = HTTParty.get("#{base_uri}/#{caminho}",
                            query: { fields: campos, access_token: canal.access_token },
                            headers: { 'Accept' => 'application/json' })
    return resposta.parsed_response if resposta.success? && resposta.parsed_response.is_a?(Hash)

    Rails.logger.error("[social] graph #{caminho} devolveu HTTP #{resposta.code}")
    nil
  end

  def ligada?
    ((publicacao.account.settings || {})['social_reply'] || {})['ler_midia'].present?
  end

  # Encarte não muda depois de publicado; reler é queimar visão à toa. A janela existe só para
  # o caso de a primeira leitura ter pegado a mídia ainda processando.
  def recente?
    publicacao.lida_em.present? && publicacao.lida_em > JANELA.ago
  end

  def canal
    @canal ||= publicacao.inbox.channel
  end

  def base_uri
    "https://graph.instagram.com/#{GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0')}"
  end
end
