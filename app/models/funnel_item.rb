# frozen_string_literal: true

# == Schema Information
#
# Table name: funnel_items
#
#  id              :bigint           not null, primary key
#  moved_at        :datetime
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  conversation_id :bigint           not null
#  funnel_id       :bigint           not null
#  funnel_stage_id :bigint           not null
#  moved_by_id     :bigint
#
# Indexes
#
#  index_funnel_items_on_conversation_id  (conversation_id)
#  index_funnel_items_on_funnel_id        (funnel_id)
#  index_funnel_items_on_funnel_stage_id  (funnel_stage_id)
#  index_funnel_items_on_moved_by_id      (moved_by_id)
#  index_funnel_items_unique              (conversation_id,funnel_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (funnel_id => funnels.id)
#  fk_rails_...  (funnel_stage_id => funnel_stages.id)
#  fk_rails_...  (moved_by_id => users.id)
#
class FunnelItem < ApplicationRecord
  belongs_to :conversation
  belongs_to :funnel
  belongs_to :funnel_stage
  belongs_to :moved_by, class_name: 'User', optional: true

  validates :conversation_id, presence: true
  validates :funnel_id, presence: true
  validates :funnel_stage_id, presence: true
  validates :conversation_id, uniqueness: { scope: :funnel_id, message: 'já está neste funil' }

  before_save :set_moved_at, if: :will_save_change_to_funnel_stage_id?

  scope :by_funnel, ->(funnel_id) { where(funnel_id: funnel_id) }
  scope :by_stage, ->(stage_id) { where(funnel_stage_id: stage_id) }

  private

  def set_moved_at
    self.moved_at = Time.current
  end
end

