# Renderiza um relatorio brandeado ChatSPX em PDF. Generico por natureza:
# o report_type seleciona o resolver de dados e o template; o shell
# (layout + css SPX) e compartilhado. Espelha Conversations::PdfExportService.
class Reports::PdfExportService
  include Reports::PdfAssetHelper # pdf_public_image_data_uri p/ logo no header impresso

  Result = Struct.new(:bytes, :sha256, keyword_init: true)

  def initialize(export:)
    @export = export
    @account = export.account
    @report_type = export.report_type
    @filters = (export.filters || {}).with_indifferent_access
  end

  def call
    data = Reports::PdfDataResolver.new(
      account: @account, report_type: @report_type, filters: @filters
    ).resolve
    html = render_html(data)
    bytes = render_pdf(html, data[:title])
    Result.new(bytes: bytes, sha256: Digest::SHA256.hexdigest(bytes))
  end

  private

  def render_html(data)
    ApplicationController.renderer.render(
      template: "reports/pdf/#{@report_type}",
      layout: 'reports/pdf',
      assigns: {
        data: data,
        export: @export,
        account: @account,
        generated_at: Time.current
      }
    )
  end

  def render_pdf(html, title)
    FerrumPdf.render_pdf(
      html: html,
      pdf_options: {
        format: :A4,
        print_background: true,
        prefer_css_page_size: true,
        display_header_footer: true,
        # Faixa de marca (cabecalho nativo) em TODA pagina — render confiavel em
        # qualquer leitor. margin_top reserva o espaco; margin_bottom o rodape.
        header_template: header_template(title),
        footer_template: footer_template,
        margin_top: 0.55,    # ~14mm: faixa de marca
        margin_bottom: 0.43, # ~11mm: rodape de paginacao
        margin_left: 0,
        margin_right: 0
      }
    )
  end

  # Faixa verde full-bleed (badge ChatSPX + titulo) repetida no topo de toda pagina.
  # print-color-adjust:exact garante o verde no print.
  # O Chromium reserva ~0.4cm de margem branca acima do header impresso; o
  # margin-top negativo (folgado) + altura extra fazem o verde sangrar ate a borda
  # da pagina (elimina QUALQUER "linha branca" no topo — o excedente e cortado na
  # borda fisica). O padding-top recoloca o conteudo no centro da faixa visivel.
  def header_template(title)
    icon = pdf_public_image_data_uri('android-icon-36x36.png')
    # Icone ChatSPX (verde) recolorido p/ branco via filtro — fundo 100% verde, sem badge.
    icon_style = 'width:14px;height:14px;display:block;flex:none;' \
                 'filter:brightness(0) invert(1);-webkit-filter:brightness(0) invert(1);'
    icon_html = icon ? %(<img src="#{icon}" style="#{icon_style}">) : ''
    <<~HTML
      <div style="width:100%;height:calc(100% + 0.8cm);margin-top:-0.7cm;
                  padding:0.7cm 14mm 0;box-sizing:border-box;
                  background:#1ea65b;-webkit-print-color-adjust:exact;print-color-adjust:exact;
                  color:#ffffff;font-family:Arial,sans-serif;display:flex;align-items:center;
                  gap:7px;font-size:10px;">
        #{icon_html}
        <span style="font-weight:bold;font-size:11px;">ChatSPX</span>
        <span style="opacity:0.55;">·</span>
        <span style="opacity:0.95;">#{ERB::Util.h(title)}</span>
      </div>
    HTML
  end

  def footer_template
    <<~HTML
      <div style="font-size:8px;width:100%;padding:0 14mm;color:#8696a0;
                  display:flex;justify-content:flex-end;font-family:Arial,sans-serif;">
        <span>Página <span class="pageNumber"></span> de <span class="totalPages"></span></span>
      </div>
    HTML
  end
end
