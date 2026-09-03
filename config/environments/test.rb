# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

require 'active_support/core_ext/integer/time'

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  config.cache_classes = false

  # Do not eager load code on boot. This avoids loading your whole application
  # just for the purpose of running a single test. If you are using a tool that
  # preloads Rails for running tests, you may have to set it to true.
  config.eager_load = false

  # Configure public file server for tests with Cache-Control for performance.
  config.public_file_server.enabled = true
  config.public_file_server.headers = {
    'Cache-Control' => "public, max-age=#{1.hour.to_i}"
  }
  config.action_mailer.default_url_options = { host: 'http://localhost:3000' }
  Rails.application.routes.default_url_options = { host: 'http://localhost:3000' }

  # Show full error reports and disable caching.
  # `false` de proposito: com `true`, qualquer excecao que chega ao middleware faz o
  # `DebugExceptions` montar a pagina de debug, que chama
  # `ActionView::Template::Handlers::ERB#find_offset` para mapear a linha do template ERB.
  # Esse metodo, no actionview 7.1.5.2, entra em LACO INFINITO (Kernel#loop + StringScanner)
  # e trava a suite inteira — 1 core cheio, I/O zero, sem nunca terminar.
  # Intermitente porque depende de qual excecao ocorre, e so aparece sob carga (contencao
  # gera timeouts que viram excecoes). Backtrace em
  # vault/00-Inbox/backtrace-travamento-rspec-21ago.txt
  # Com `false`, o Rails serve a pagina estatica de erro: nao ha `source_extracts`, nao ha
  # `find_offset`, nao ha laco. Nenhum spec do repo depende do conteudo da pagina de debug.
  config.consider_all_requests_local       = false
  config.action_controller.perform_caching = false
  config.cache_store = :null_store

  # Raise exceptions instead of rendering exception templates.
  config.action_dispatch.show_exceptions = true

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Store uploaded files on the local file system in a temporary directory.
  config.active_storage.service = :test

  config.action_mailer.perform_caching = false

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test
  config.active_job.queue_adapter = :test

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raises error for missing translations.
  # config.action_view.raise_on_missing_translations = true
  config.log_level = ENV.fetch('LOG_LEVEL', 'debug').to_sym
end
