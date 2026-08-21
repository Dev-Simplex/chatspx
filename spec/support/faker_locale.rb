# frozen_string_literal: true

# O Faker escolhe o idioma dos dados por `I18n.locale`. Como a aplicacao roda em `pt_BR` por
# padrao e o fallback `pt_BR -> pt-BR` (config/application.rb) passou a alcancar os arquivos do
# gem, o Faker comecou a gerar nomes BRASILEIROS nos testes.
#
# Isso quebra dado gerado a partir do nome. A fabrica de usuario monta
# `email { display_name + "@#{uuid}.com" }` — com "João Silva" o e-mail sai invalido e o
# `create(:user)` levanta `RecordInvalid: Email não é válido`.
#
# O efeito so aparece FORA do `I18n.with_locale(:en)` do rails_helper — em `before_all`
# (test-prof), por exemplo, que roda antes do wrapper. Por isso derrubou um arquivo inteiro
# (report_builder_spec, 21 exemplos) e nenhum outro.
#
# Dado de teste nao deve depender do idioma da aplicacao: fixamos o Faker em :en para ele ser
# deterministico e ASCII, sem mexer no locale do app.
Faker::Config.locale = :en
