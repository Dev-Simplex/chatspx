# frozen_string_literal: true

# Configura cliente Ferrum (Chromium headless via CDP) para geracao
# de PDFs server-side. Usado por Conversations::PdfExportService.
#
# Em producao do Chat SPX o chromium e instalado via snap:
#   /snap/bin/chromium
# Sem sandbox porque o usuario chatwoot nao tem cap_sys_admin.

require 'ferrum_pdf'

FerrumPdf.configure do |config|
  config.browser_path = ENV.fetch('CHROMIUM_PATH', '/snap/bin/chromium')
  config.browser_options = {
    'no-sandbox': nil,
    'disable-dev-shm-usage': nil,
    'disable-gpu': nil,
    'headless': 'new'
  }
  config.timeout = 120
  config.process_timeout = 120
  config.window_size = [1280, 1696]
  config.pdf_options = {
    format: :A4,
    print_background: true,
    prefer_css_page_size: true
  }
end
