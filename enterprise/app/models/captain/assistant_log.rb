class Captain::AssistantLog < ApplicationRecord
  self.table_name = 'captain_assistant_logs'

  belongs_to :captain_assistant, class_name: 'Captain::Assistant'
  belongs_to :conversation, class_name: '::Conversation', optional: true

  # mirror_assigned/mirror_released/human_takeover: trilha de auditoria da atribuição
  # do espelho captain (Fase E/E4 — watcher em Enterprise::Concerns::Conversation).
  # handoff_auto_fired/dedup_regenerate/unknown_marker: emitidos pelo ResponseBuilderJob e que
  # NUNCA estiveram nesta lista — o create! levantava RecordInvalid, o rescue do chamador engolia
  # e o comportamento que vinha DEPOIS do log nunca acontecia (o safety-net de handoff e o
  # backstop anti-repeticao ficaram mortos em producao por isso). Declarar aqui e obrigatorio.
  EVENT_TYPES = %w[
    response debounce_skip debounce_fire router_skip business_hours_skip
    handoff media_process humanizer_split dedup_skip error copilot_trigger
    mirror_assigned mirror_released human_takeover ignored
    handoff_auto_fired dedup_regenerate unknown_marker
  ].freeze

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }

  scope :ordered, -> { order(created_at: :desc) }
  scope :by_event_type, ->(type) { where(event_type: type) if type.present? }
end
