class FkCascadeNosFilhosDeConversation < ActiveRecord::Migration[7.1]
  # Quatro tabelas nossas apontavam para `conversations` com FK sem `on_delete`, que
  # no Postgres e RESTRICT. Efeito: toda conversa que a IA ou um flow tocou virava
  # indestrutivel, e junto com ela o contato, a caixa de entrada e a conta.
  #
  # Como exclusao de caixa/conversa/conta roda em background (DeleteObjectJob), a
  # falha era SILENCIOSA: a API respondia 200 com "excluida", o job morria com
  # PG::ForeignKeyViolation e o objeto reaparecia no proximo reload. Ja a exclusao
  # de contato e sincrona, entao aparecia como 500 na tela.
  #
  # Diagnosticado na FABRICA em 08/09/2026 (inbox 2, 4 tentativas na fila de mortos)
  # e confirmado na TOZI e na AGN, onde 70% das conversas estavam travadas.
  #
  # CASCADE e a unica saida: `conversation_id` e NOT NULL em flow_runs e em
  # message_sequence_enrollments, entao nullify nao e opcao.
  TABELAS = %w[
    captain_assistant_logs
    flow_runs
    flow_step_logs
    message_sequence_enrollments
  ].freeze

  def up
    each_tabela do |tabela|
      remove_foreign_key tabela, :conversations
      add_foreign_key tabela, :conversations, on_delete: :cascade
    end
  end

  def down
    each_tabela do |tabela|
      remove_foreign_key tabela, :conversations
      add_foreign_key tabela, :conversations
    end
  end

  private

  # A frota nao esta toda no mesmo ponto do historico: VM que ainda nao tem a tabela
  # (ou que ja perdeu a FK) so e pulada, em vez de derrubar o db:migrate inteiro.
  def each_tabela
    TABELAS.each do |tabela|
      next unless table_exists?(tabela)
      next unless foreign_key_exists?(tabela, :conversations)

      yield tabela
    end
  end
end
