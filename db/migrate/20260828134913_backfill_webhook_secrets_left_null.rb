# O backfill de 20260324070835 encheu a coluna UMA vez. Depois dele, `AgentBot` e
# `Channel::Api` ficaram sem `has_secure_token :secret` nesta arvore — entao todo registro
# criado desde entao nasceu com `secret` NULL, e webhook sem segredo sai SEM assinatura.
#
# Medido em homologacao antes desta mudanca: 1 de 11 agent bots com NULL (13 de 13 canais
# API ok). Reexecutar a migration antiga nao resolveria — a versao dela ja esta gravada em
# `schema_migrations` da frota inteira, e ela nunca mais roda.
#
# So toca quem esta NULL: trocar um segredo ja combinado com o destino quebraria a
# verificacao do outro lado na entrega seguinte.
class BackfillWebhookSecretsLeftNull < ActiveRecord::Migration[7.1]
  def up
    AgentBot.reset_column_information
    Channel::Api.reset_column_information

    [AgentBot, Channel::Api].each do |model|
      model.where(secret: nil).find_each do |record|
        record.secret = SecureRandom.urlsafe_base64(24)
        record.save!(validate: false)
      end
    end
  end

  def down
    # no-op: nao ha como saber quais linhas estavam NULL antes, e apagar segredo em uso
    # derrubaria a assinatura de quem ja esta integrado.
  end
end
