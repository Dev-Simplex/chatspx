# Renderiza um relatorio brandeado ChatSPX em PDF. Generico por natureza:
# o report_type seleciona o resolver de dados e o template; o shell
# (layout + css SPX) e compartilhado. Espelha Conversations::PdfExportService.
class Reports::PdfExportService
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

  # Faixa verde full-bleed (logo SPX branco + ChatSPX + titulo) repetida no topo de
  # toda pagina. print-color-adjust:exact garante o verde no print.
  def header_template(title)
    <<~HTML
      <div style="width:100%;height:100%;margin:0;box-sizing:border-box;
                  background:#1ea65b;-webkit-print-color-adjust:exact;print-color-adjust:exact;
                  color:#ffffff;font-family:Arial,sans-serif;display:flex;align-items:center;
                  gap:7px;padding:0 14mm;font-size:10px;">
        <svg width="13" height="13" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg">
          <path d="M8 16C12.4183 16 16 12.4183 16 8C16 3.58172 12.4183 0 8 0C3.58172 0 0 3.58172 0 8C0 12.4183 3.58172 16 8 16Z" fill="#ffffff"/>
          <path d="M11.4172 11.4172H7.70831C5.66383 11.4172 4 9.75328 4 7.70828C4 5.66394 5.66383 4 7.70835 4C9.75339 4 11.4172 5.66394 11.4172 7.70828V11.4172Z" fill="#1ea65b"/>
        </svg>
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
