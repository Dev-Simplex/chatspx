# URL canônica do imóvel no site do cliente — extraída verbatim da buscar_imovel pra ser
# compartilhada com enviar_fotos (modo ver_detalhes do carrossel). A trava de link da conduta
# só permite URLs com este padrão, então TODA URL de imóvel deve nascer aqui.
# `site_domain` vem do IntegrationCredentials (por conta).
module Captain::Tools::VistaImovelUrl
  # O site acha o imóvel pelo ImoCodigo (não pelo Codigo do Vista); o slug é cosmético.
  # Padrão observado: {finalidade}-{categoria}-{N}-dormitorios-{bairroComercial}-{cidade},{ImoCodigo}
  def build_url(im, venda)
    bairro = im['BairroComercial'].presence || im['Bairro']
    parts = [venda ? 'venda' : 'aluguel', slugify(im['Categoria'])]
    parts << "#{im['Dormitorios']}-dormitorios" if im['Dormitorios'].to_i.positive?
    parts << slugify(bairro) << slugify(im['Cidade'])
    id = im['ImoCodigo'].presence || im['Codigo']
    "https://www.#{site_domain}/#{parts.reject(&:blank?).join('-')},#{id}"
  end

  def slugify(str)
    str.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '')
       .downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')
  end
end
