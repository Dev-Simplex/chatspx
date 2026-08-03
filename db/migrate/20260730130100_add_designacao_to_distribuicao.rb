# Terceiro estado: DESIGNADO (docs/clientes/tozi/SPEC-RODIZIO.md §3 e §5).
#
# `modo_posse` decide se o Motor ATRIBUI (assignee humano, IA cala — comportamento atual
# dos times que vivem dentro do SPX) ou apenas DESIGNA (assignee segue nulo, o espelho
# captain sobrevive e a IA continua atendendo até alguém assumir de fato).
# Default 'assignee' => nenhuma política existente muda de comportamento.
#
# Os campos novos do log transformam a linha de auditoria no LIVRO-RAZÃO da designação:
# quem, quando, sob qual regra, e quando encerrou.
#
# Additiva e inerte. Aplicar com alvo específico
# (db:migrate:up VERSION=20260730130100) para não disparar migrations destrutivas pendentes.
class AddDesignacaoToDistribuicao < ActiveRecord::Migration[7.1]
  def change
    add_column :distribuicao_policies, :modo_posse, :string, null: false, default: 'assignee'

    add_column :distribuicao_logs, :status, :string
    add_column :distribuicao_logs, :designado_em, :datetime
    add_column :distribuicao_logs, :encerrado_em, :datetime
    # A regra que valeu NA HORA. Sem isto, mudar o pool amanhã apaga a explicação de ontem.
    add_column :distribuicao_logs, :policy_snapshot, :jsonb, null: false, default: {}
    add_column :distribuicao_logs, :vista_negocio_codigo, :string

    # Serve as duas leituras quentes: a designação aberta de uma conversa e a lista
    # "designados há mais de X sem movimento" da tela do gestor.
    add_index :distribuicao_logs, %i[status designado_em]
  end
end
