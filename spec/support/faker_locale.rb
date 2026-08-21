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

# ...e a atribuicao acima NAO basta. `Faker::Config.locale=` grava em
# `Thread.current[:faker_config_locale]` — e o getter cai em `I18n.locale` quando a chave nao
# existe. Ou seja: vale so para a thread que executou esta linha. Qualquer exemplo que crie uma
# thread (o de corrida em `send_email_notification_service_spec`, por exemplo) monta a fabrica
# de usuario com Faker em pt_BR de novo, e volta o mesmo `RecordInvalid: Email nao e valido` --
# de forma INTERMITENTE, porque so quebra quando o nome sorteado tem acento. Passou 3 vezes
# seguidas e falhou 4 seguidas na mesma arvore; parecia carga da maquina e nao era: e o sorteio.
#
# Corrigir o VALOR numa thread nao resolve para as proximas. Corrigimos o FALLBACK: sem chave
# thread-local, o padrao passa a ser :en em vez de `I18n.locale`. Atribuicao explicita
# (`Faker::Config.locale = :pt_BR` num spec) continua vencendo, porque a chave thread-local
# tem prioridade.
module FakerLocalePadraoEn
  def locale
    Thread.current[:faker_config_locale] || :en
  end
end

Faker::Config.singleton_class.prepend(FakerLocalePadraoEn)
