# == Schema Information
#
# Table name: captain_inboxes
#
#  id                   :bigint           not null, primary key
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  captain_assistant_id :bigint           not null
#  inbox_id             :bigint           not null
#
# Indexes
#
#  index_captain_inboxes_on_captain_assistant_id               (captain_assistant_id)
#  index_captain_inboxes_on_captain_assistant_id_and_inbox_id  (captain_assistant_id,inbox_id) UNIQUE
#  index_captain_inboxes_on_inbox_id                           (inbox_id)
#
class CaptainInbox < ApplicationRecord
  belongs_to :captain_assistant, class_name: 'Captain::Assistant'
  belongs_to :inbox

  # Elegibilidade do PAR (A5): espelha o índice único DB (captain_assistant_id, inbox_id).
  # Permite N assistants elegíveis na mesma inbox; bloqueia o mesmo assistant 2× na inbox.
  validates :inbox_id, uniqueness: { scope: :captain_assistant_id }
end
