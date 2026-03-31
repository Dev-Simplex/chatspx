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
# Index: (conversation_id, funnel_id) UNIQUE
#
class FunnelItem < ApplicationRecord
  belongs_to :conversation
  belongs_to :funnel
  belongs_to :funnel_stage
  belongs_to :moved_by, class_name: 'User', optional: true

  validates :conversation_id, presence: true
  validates :funnel_id, presence: true
  validates :funnel_stage_id, presence: true
  validates :conversation_id, uniqueness: { scope: :funnel_id, message: 'already in this funnel' } # rubocop:disable Rails/I18nLocaleTexts

  before_save :set_moved_at, if: :will_save_change_to_funnel_stage_id?

  scope :by_funnel, ->(funnel_id) { where(funnel_id: funnel_id) }
  scope :by_stage, ->(stage_id) { where(funnel_stage_id: stage_id) }

  private

  def set_moved_at
    self.moved_at = Time.current
  end
end
