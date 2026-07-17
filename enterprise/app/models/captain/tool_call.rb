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
end
