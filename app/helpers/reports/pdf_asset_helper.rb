# Embute fontes (e, se preciso, logos) como base64 diretamente no HTML.
# O Chromium do ferrum_pdf roda server-side e (no snap) e confinado: nao le
# /tmp nem garante acesso a assets por caminho. base64 inline evita o problema
# e impede que as fontes caiam em fallback. Os WOFF2 do Vite tem hash no nome,
# entao resolvemos por glob de prefixo (nao hardcode do hash).
module Reports::PdfAssetHelper
  FONTS = [
    { family: 'Inter',        weight: 400, prefix: 'Inter-Regular' },
    { family: 'Inter',        weight: 500, prefix: 'Inter-Medium' },
    { family: 'Inter',        weight: 600, prefix: 'Inter-SemiBold' },
    { family: 'Inter',        weight: 700, prefix: 'Inter-Bold' },
    { family: 'InterDisplay', weight: 600, prefix: 'InterDisplay-SemiBold' },
    { family: 'InterDisplay', weight: 700, prefix: 'InterDisplay-Bold' },
    { family: 'InterDisplay', weight: 800, prefix: 'InterDisplay-ExtraBold' }
  ].freeze

  VITE_ASSETS = Rails.public_path.join('vite/assets')

  # Embute uma imagem de /public como data URI base64. O Chromium do ferrum_pdf
  # (snap, confinado) nao le assets por caminho — inline e o unico jeito confiavel,
  # inclusive dentro do header_template impresso. Retorna nil se ausente.
  def pdf_public_image_data_uri(filename, mime: 'image/png')
    path = Rails.public_path.join(filename)
    return nil unless File.exist?(path)

    "data:#{mime};base64,#{Base64.strict_encode64(File.binread(path))}"
  rescue StandardError => e
    Rails.logger.warn("[report_pdf] imagem #{filename} indisponivel: #{e.message}")
    nil
  end

  def pdf_font_face_css
    FONTS.filter_map do |font|
      data = font_data_uri(font[:prefix])
      next if data.nil?

      <<~CSS
        @font-face {
          font-family: '#{font[:family]}';
          font-style: normal;
          font-weight: #{font[:weight]};
          font-display: block;
          src: url(#{data}) format('woff2');
        }
      CSS
    end.join("\n").html_safe # rubocop:disable Rails/OutputSafety
  end

  private

  def font_data_uri(prefix)
    path = font_path(prefix)
    return nil if path.nil?

    "data:font/woff2;base64,#{Base64.strict_encode64(File.binread(path))}"
  rescue StandardError => e
    Rails.logger.warn("[report_pdf] fonte #{prefix} indisponivel: #{e.message}")
    nil
  end

  def font_path(prefix)
    Dir.glob(VITE_ASSETS.join("#{prefix}-*.woff2")).min
  end
end
