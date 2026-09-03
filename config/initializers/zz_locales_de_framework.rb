# frozen_string_literal: true

# `I18n::Backend::Simple#store_translations` DESCARTA, na hora de carregar, qualquer locale que
# nao esteja em `I18n.available_locales` (quando `enforce_available_locales` esta ligado). Como o
# Chatwoot registra `pt_BR` (sublinhado) e o gem `rails-i18n` publica `pt-BR` (hifen), os dados do
# gem eram jogados fora no carregamento — e o fallback configurado em `config/application.rb` caia
# no `pt` de PORTUGAL, que esta na lista. O sintoma era texto europeu numa aplicacao brasileira:
# "é demasiado grande (o máximo é de 5 caracteres)" no lugar de
# "é muito longo (máximo: 5 caracteres)".
#
# Registrar as grafias com hifen faz os arquivos do gem serem ARMAZENADOS, e ai o fallback
# `pt_BR -> pt-BR -> pt` encontra o texto certo no primeiro salto. Elas nao viram idioma
# escolhivel: a lista de produto e a `LANGUAGES_CONFIG` de `languages.rb`, nao esta.
#
# Prefixo `zz_` de proposito: os initializers rodam em ordem alfabetica e este precisa vir DEPOIS
# de `languages.rb`, que monta a lista base.
Rails.configuration.i18n.available_locales |= %i[pt-BR zh-CN zh-TW]
