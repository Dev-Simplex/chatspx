# Configuração de I18n para Chatwoot
# Define o locale padrão para português brasileiro
# Isso garante que todos os emails sejam enviados em pt-BR quando não houver
# um locale específico configurado na conta

Rails.application.config.i18n.default_locale = ENV.fetch('DEFAULT_LOCALE', 'pt_BR').to_sym

