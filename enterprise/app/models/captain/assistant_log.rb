class Captain::AssistantLog < ApplicationRecord
  self.table_name = 'captain_assistant_logs'

  belongs_to :captain_assistant, class_name: 'Captain::Assistant'
  belongs_to :conversation, optional: true

  EVENT_TYPES = %w[
    response debounce_skip debounce_fire router_skip business_hours_skip
    handoff media_process humanizer_split dedup_skip error copilot_trigger
  ].freeze

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }

  scope :ordered, -> { order(created_at: :desc) }
  scope :by_event_type, ->(type) { where(event_type: type) if type.present? }
end
