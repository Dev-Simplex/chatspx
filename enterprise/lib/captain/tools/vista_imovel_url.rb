# URL da página do imóvel no site do cliente — compartilhada entre buscar_imovel e
# enviar_fotos (modo ver_detalhes do carrossel). A trava de link da conduta só deixa
# passar URL do domínio do cliente, então TODA URL de imóvel deve nascer aqui.
#
# Fonte da verdade é a API do site (`GET /imoveis/:codigo/link`), que devolve o
# caminho canônico. O HOST dela é interno; quem vai pro cliente é sempre o domínio
# público da conta (`site_domain`) — por isso trocamos o host e mantemos o caminho.
#
# Sem chave configurada, ou se a API falhar, cai no formato montado localmente. Esse
# formato é o do site atual (`/imovel/<slug>-<codigo>`): o slug é cosmético — o site
# resolve pelo código no fim e redireciona pro canônico — mas o prefixo `/imovel/` e o
# hífen antes do código são obrigatórios (o formato antigo `...,codigo` dá 404).
module Captain::Tools::VistaImovelUrl
  SITE_LINK_TIMEOUT = 5
  SITE_LINK_TTL = 12.hours

  def build_url(im, venda)
    codigo = imovel_codigo(im)
    site_api_link(codigo) || fallback_url(im, venda, codigo)
  end

  def slugify(str)
    str.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '')
       .downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')
  end

  private

  # A API do site recebe o código do Vista — o mesmo que a busca devolve ao agente.
  def imovel_codigo(imovel)
    imovel['Codigo'].presence || imovel['ImoCodigo']
  end

  # Caminho canônico da API do site, remontado no domínio público da conta.
  # Só o sucesso é cacheado: falha volta a tentar na próxima chamada.
  def site_api_link(codigo)
    return nil if codigo.blank? || site_api_key.blank?

    Rails.cache.fetch("spx:imovel_url:#{site_domain}:#{codigo}", expires_in: SITE_LINK_TTL, skip_nil: true) do
      public_site_url(fetch_site_link(codigo))
    end
  rescue StandardError => e
    Rails.logger.warn("[VistaImovelUrl] link do site falhou pro imóvel #{codigo}: #{e.message}")
    nil
  end

  def fetch_site_link(codigo)
    resp = HTTParty.get(
      "#{site_api_url.to_s.chomp('/')}/imoveis/#{codigo}/link",
      headers: { 'x-api-key' => site_api_key, 'Accept' => 'application/json' },
      timeout: SITE_LINK_TIMEOUT
    )
    return nil unless resp.code == 200

    body = resp.parsed_response
    body = JSON.parse(body) if body.is_a?(String)
    body.is_a?(Hash) ? body.dig('data', 'url') : nil
  end

  # Mantém o caminho que a API devolveu, troca o host pelo domínio público.
  def public_site_url(raw)
    path = URI.parse(raw.to_s).path.presence
    return nil if path.blank? || path == '/'

    "https://www.#{site_domain}#{path}"
  rescue URI::InvalidURIError
    nil
  end

  def fallback_url(imovel, venda, codigo)
    bairro = imovel['BairroComercial'].presence || imovel['Bairro']
    parts = [venda ? 'venda' : 'aluguel', slugify(imovel['Categoria']), slugify(bairro), slugify(imovel['Cidade'])]
    "https://www.#{site_domain}/imovel/#{parts.reject(&:blank?).join('-')}-#{codigo}"
  end
end
