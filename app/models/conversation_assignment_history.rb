# == Schema Information
#
# Table name: conversation_assignment_histories
#
#  id              :bigint           not null, primary key
#  assigned_at     :datetime         not null
#  source          :integer          default("unknown"), not null
#  unassigned_at   :datetime
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  assigned_by_id  :bigint
#  assignee_id     :bigint
#  conversation_id :bigint           not null
#  team_id         :bigint
#
# Registro estruturado de cada mudança de responsável (assignee) de uma conversa.
# Alimenta o Relatório de Atribuições por Agente: guarda QUEM atribuiu (`assigned_by_id`),
# PRA QUEM (`assignee_id`), a ORIGEM (`source`) e o intervalo (`assigned_at`/`unassigned_at`).
# Escrito best-effort por Conversations::AssignmentHistoryService (nunca quebra a atribuição).
class ConversationAssignmentHistory < ApplicationRecord
  belongs_to :account
  belongs_to :conversation
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :assigned_by, class_name: 'User', optional: true
  belongs_to :team, optional: true

  enum source: {
    manual: 0,            # humano atribuiu (pra outra pessoa)
    self_assigned: 1,     # a própria pessoa pegou pra si
    auto_round_robin: 2,  # atribuição automática (política/inbox)
    automation: 3,        # regra de automação
    bot: 4,               # handoff de bot/Captain
    api: 5,               # via API pública
    unknown: 6            # origem indeterminada
  }

  scope :in_range, ->(range) { where(assigned_at: range) }
end
