# frozen_string_literal: true

# == Schema Information
#
# Table name: funnel_item_notes
#
#  id             :bigint           not null, primary key
#  content        :text             not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  funnel_item_id :bigint           not null
#  user_id        :bigint
#
# Kanban v2 (Fase 4): an internal note on a card (not sent to the customer).
class FunnelItemNote < ApplicationRecord
  belongs_to :funnel_item
  belongs_to :user, optional: true

  validates :content, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
end
