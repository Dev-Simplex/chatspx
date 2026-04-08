# == Schema Information
#
# Table name: nps_responses
#
#  id                :bigint           not null, primary key
#  account_id        :bigint           not null
#  conversation_id   :bigint           not null
#  contact_id        :bigint           not null
#  inbox_id          :bigint           not null
#  assigned_agent_id :bigint
#  status            :integer          default("pending"), not null
#  score             :integer
#  comment           :text
#  sent_at           :datetime
#  answered_at       :datetime
#  dismiss_reason    :string
#  blocked_by_label  :string
#  blocked_scope     :integer
#  metadata          :jsonb
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
# Indexes
#
#  index_nps_responses_on_account_id         (account_id)
#  index_nps_responses_on_conversation_id    (conversation_id) UNIQUE
#  index_nps_responses_on_contact_id         (contact_id)
#  index_nps_responses_on_inbox_id           (inbox_id)
#  index_nps_responses_on_assigned_agent_id  (assigned_agent_id)
#  index_nps_responses_on_account_id_and_sent_at      (account_id, sent_at)
#  index_nps_responses_on_account_id_and_answered_at  (account_id, answered_at)
#  index_nps_responses_on_contact_id_and_answered_at  (contact_id, answered_at)
#  index_nps_responses_on_status             (status)
#
class NpsResponse < ApplicationRecord
  belongs_to :account
  belongs_to :conversation
  belongs_to :contact
  belongs_to :inbox
  belongs_to :assigned_agent, class_name: 'User', optional: true

  enum status: {
    pending: 0,
    sent: 1,
    responded: 2,
    expired: 3,
    dismissed: 4
  }

  enum blocked_scope: {
    contact: 0,
    conversation: 1
  }

  validates :account_id, presence: true
  validates :contact_id, presence: true
  validates :conversation_id, presence: true
  validates :inbox_id, presence: true
  validates :score, inclusion: { in: 0..10 }, allow_nil: true

  scope :filter_by_created_at, lambda { |range|
    return all if range.blank?

    start_date = range.first
    end_date = range.last

    # Use answered_at for responded (if present), otherwise use created_at
    # For non-responded, use created_at
    # This ensures we filter by when the response was actually given or when it was created
    responded_status = statuses[:responded]
    where(
      '(status = ? AND answered_at IS NOT NULL AND answered_at BETWEEN ? AND ?) OR ' \
      '(status = ? AND answered_at IS NULL AND created_at BETWEEN ? AND ?) OR ' \
      '(status != ? AND created_at BETWEEN ? AND ?)',
      responded_status, start_date, end_date,
      responded_status, start_date, end_date,
      responded_status, start_date, end_date
    )
  }
  scope :filter_by_assigned_agent_id, ->(user_ids) { where(assigned_agent_id: user_ids) if user_ids.present? }
  scope :filter_by_inbox_id, ->(inbox_id) { where(inbox_id: inbox_id) if inbox_id.present? }
  scope :filter_by_status, ->(status) { where(status: status) if status.present? }
  scope :filter_by_response_state, lambda { |state|
    return all if state.blank?

    case state.to_s
    when 'responded' then where(status: :responded)
    when 'not_responded' then where(status: %i[pending sent expired dismissed])
    else all
    end
  }
  scope :filter_by_score_range, ->(min, max) { where(score: min..max) if min.present? && max.present? }
  scope :promoters, -> { where(score: 9..10) }
  scope :passives, -> { where(score: 7..8) }
  scope :detractors, -> { where(score: 0..6) }
  scope :responded, -> { where(status: :responded) }
  scope :active, -> { where(status: [:sent, :pending]) }
  scope :trusted, -> { where(data_quality_flag: [nil, 'verified']) }
  scope :flagged, -> { where.not(data_quality_flag: [nil, 'verified']) }

  def promoter?
    score.present? && score >= 9 && score <= 10
  end

  def passive?
    score.present? && score >= 7 && score <= 8
  end

  def detractor?
    score.present? && score >= 0 && score <= 6
  end

  def expired?
    return false unless sent?
    return false if sent_at.blank?

    expiration_hours = inbox.nps_config&.dig('expiration_hours') || 72
    sent_at < expiration_hours.hours.ago
  end

  def can_resend?
    return false if responded?
    return false if dismissed?
    return true if expired?
    return false if sent?

    true
  end

  def classification
    return nil if score.blank?

    if promoter?
      'promoter'
    elsif passive?
      'passive'
    elsif detractor?
      'detractor'
    end
  end
end
