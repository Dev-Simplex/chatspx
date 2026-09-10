# Trace de uma chamada de ferramenta da IA (Eval 2.0 F2). Alimenta o juiz
# (tool calls inline no transcript) e o gate determinístico (retorno × resposta).
class Captain::ToolCall < ApplicationRecord
  self.table_name = 'captain_tool_calls'

  belongs_to :account
  belongs_to :conversation, class_name: '::Conversation'

  validates :tool_name, presence: true

  scope :for_conversation, ->(conversation_id) { where(conversation_id: conversation_id) }
  scope :in_window, ->(from, to) { where(created_at: from..to) }
  scope :with_error, -> { where(status: 'error') }

  # Duas features querem o mesmo trace por motivos diferentes: o Eval, para julgar o
  # atendimento depois, e a ToolContextNote, para devolver o retorno ao contexto do próximo
  # turno. Sem este OR, ligar o contexto numa conta sem eval não gravaria nada e a nota
  # nasceria sempre vazia — falha silenciosa.
  def self.gravar_para?(account)
    return false if account.blank?

    Captain::ConversationEval.enabled_for?(account).present? ||
      Captain::Conversation::ToolContextNote.enabled_for?(account)
  end
end
