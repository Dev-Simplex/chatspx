# A coluna ja existe no schema.rb e no banco de toda a frota, mas o ARQUIVO da migration
# tinha sumido: `db/migrate` nao continha nada que a criasse. Em banco ja migrado isso nao
# aparece — a versao esta gravada em `schema_migrations` e ninguem repara. Aparece numa
# instalacao NOVA por `db:migrate`, que nasceria sem a coluna e derrubaria o AgentBot na
# primeira leitura de `secret`.
#
# `if_not_exists` porque em todo banco que ja rodou a versao antiga a coluna esta la: a
# migration precisa ser inofensiva se alguem reexecutar do zero contra um banco populado.
class AddSecretToAgentBots < ActiveRecord::Migration[7.1]
  def change
    add_column :agent_bots, :secret, :string, if_not_exists: true
  end
end
