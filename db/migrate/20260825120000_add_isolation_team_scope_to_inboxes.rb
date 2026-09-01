class AddIsolationTeamScopeToInboxes < ActiveRecord::Migration[7.1]
  # Escopo POR TIME das 3 regras de isolamento da caixa. A flag booleana continua
  # ligando/desligando a regra; a lista diz EM QUAIS times ela vale.
  #
  # Array de bigint (e nao jsonb/tabela de juncao) porque o custo real esta nos
  # pontos de LEITURA: as listagens (conversation_finder, list_preloader,
  # search_service) montam SQL cru e precisam da checagem por LINHA — com
  # `conversations.team_id = ANY(inboxes.<col>)` isso e um operador nativo, sem
  # join extra nem cast. Com jsonb precisaria de `@>` + cast do team_id a texto;
  # com tabela de juncao, de mais um LEFT JOIN em toda listagem de conversa.
  # bigint (nao integer) para casar EXATAMENTE com `conversations.team_id` e `teams.id`,
  # que sao bigint: assim o `= ANY(...)` compara tipos iguais.
  #
  # Default `{}` = lista vazia = a regra vale para TODOS os times, que e exatamente
  # o comportamento de hoje. Nenhuma caixa ja configurada muda no deploy.
  #
  # Sem FK para `teams` (array nao suporta): id de time apagado vira lixo inerte —
  # nenhuma conversa tera aquele team_id, entao a regra so deixa de casar.
  def change
    add_column :inboxes, :team_message_isolation_team_ids, :bigint, array: true, default: [], null: false
    add_column :inboxes, :agent_message_isolation_team_ids, :bigint, array: true, default: [], null: false
    add_column :inboxes, :agent_conversation_isolation_team_ids, :bigint, array: true, default: [], null: false
  end
end
