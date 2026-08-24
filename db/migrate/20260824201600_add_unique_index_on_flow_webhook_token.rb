# O `webhook_token` é a credencial INTEIRA do endpoint público que dispara um Flow
# (Webhooks::FlowsController) e o `Flow.for_webhook_token` resolve token → flow com um `.first`,
# sem escopo de conta. Sem unicidade no banco, dois flows (de contas DIFERENTES) com o mesmo token
# fariam o lookup devolver um deles pela ordem física da tabela: o portador do token da conta A
# dispararia o flow da conta B. Até agora nada garantia isso — o token nascia de um
# SecureRandom.hex(24) (colisão desprezível), mas o cliente conseguia FIXÁ-LO num caminho de duas
# requisições (ver Flow#ensure_webhook_token), e aí escolher um valor já usado era trivial.
#
# Índice PARCIAL: só as linhas que têm token entram (a esmagadora maioria dos flows não é webhook,
# e o NULL do jsonb ausente nem seria comparável por igualdade de qualquer forma).
#
# ATENÇÃO ao rodar em base existente: se houver token duplicado a criação FALHA. Conferir antes:
#   SELECT trigger_config->>'webhook_token' AS t, count(*)
#     FROM flows WHERE trigger_config->>'webhook_token' IS NOT NULL
#    GROUP BY 1 HAVING count(*) > 1;
class AddUniqueIndexOnFlowWebhookToken < ActiveRecord::Migration[7.1]
  def change
    add_index :flows, "(trigger_config->>'webhook_token')",
              unique: true,
              where: "(trigger_config->>'webhook_token') IS NOT NULL",
              name: 'index_flows_on_webhook_token'
  end
end
