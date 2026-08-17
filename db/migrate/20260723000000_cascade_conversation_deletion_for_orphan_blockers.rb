class CascadeConversationDeletionForOrphanBlockers < ActiveRecord::Migration[7.1]
  # ChatSPX (item 26, correção (b)): quatro FKs apontam para `conversations` SEM cascade e SEM
  # `has_many ... dependent:` no Conversation, então `conversation.destroy!` levanta
  # `ActiveRecord::InvalidForeignKey`. Medido nesta VM, em information_schema:
  #
  #   captain_assistant_logs.conversation_id       NO ACTION   (nullable)
  #   flow_runs.conversation_id                    NO ACTION   (NOT NULL)
  #   flow_step_logs.conversation_id               NO ACTION   (nullable)
  #   message_sequence_enrollments.conversation_id NO ACTION   (NOT NULL)
  #
  # Isto tem de andar JUNTO com o fix da assinatura em Conversations::DeleteService: sem a FK, o
  # `destroy!` volta a rodar e falha dentro de um job COM RETRY — trocaríamos "some em silêncio"
  # por "falha em loop no GlitchTip", que é trocar um defeito por outro.
  #
  # A escolha por coluna PRESERVA o que pode ser preservado:
  #  · nullable  -> SET NULL: o log de execução/IA sobrevive à exclusão da conversa (é histórico de
  #    diagnóstico, não é conteúdo da conversa) e para de bloquear;
  #  · NOT NULL  -> CASCADE: `flow_run` e `enrollment` não existem sem a conversa (a coluna é
  #    obrigatória), e só desaparecem quando alguém apaga a conversa DE PROPÓSITO.
  #
  # `flow_step_logs.flow_run_id` também entra: sem SET NULL nele, o CASCADE de `flow_runs` falharia
  # ao encontrar logs referenciando a run que está sendo removida.
  #
  # Ver plano/redesenho/execucao/onda-0-correcoes-pendentes.md item 26 e A6 §1.1.
  NULLIFY = [
    %w[captain_assistant_logs conversation_id conversations],
    %w[flow_step_logs conversation_id conversations],
    %w[flow_step_logs flow_run_id flow_runs]
  ].freeze

  CASCADE = [
    %w[flow_runs conversation_id conversations],
    %w[message_sequence_enrollments conversation_id conversations]
  ].freeze

  def up
    NULLIFY.each { |table, column, to| replace_fk(table, column, to, :nullify) }
    CASCADE.each { |table, column, to| replace_fk(table, column, to, :cascade) }
  end

  def down
    (NULLIFY + CASCADE).each { |table, column, to| replace_fk(table, column, to, nil) }
  end

  private

  def replace_fk(table, column, to, on_delete)
    remove_foreign_key table, column: column, if_exists: true
    add_foreign_key table, to, column: column, on_delete: on_delete
  end
end
