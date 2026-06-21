class Captain::AssistantLog < ApplicationRecord
  self.table_name = 'captain_assistant_logs'

  belongs_to :captain_assistant, class_name: 'Captain::Assistant'
  belongs_to :conversation, class_name: '::Conversation', optional: true

  # mirror_assigned/mirror_released/human_takeover: trilha de auditoria da atribuição
  # do espelho captain (Fase E/E4 — watcher em Enterprise::Concerns::Conversation).
  EVENT_TYPES = %w[
    response debounce_skip debounce_fire router_skip business_hours_skip
    handoff media_process humanizer_split dedup_skip error copilot_trigger
    mirror_assigned mirror_released human_takeover
  ].freeze

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }

  scope :ordered, -> { order(created_at: :desc) }
  scope :by_event_type, ->(type) { where(event_type: type) if type.present? }
end
