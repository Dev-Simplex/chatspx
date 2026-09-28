require 'administrate/base_dashboard'

class SuggestionDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    created_at: Field::DateTime,
    source: Field::Select.with_options(collection: Suggestion.sources.keys),
    name: Field::String,
    company: Field::String,
    account: Field::BelongsTo,
    user: Field::BelongsTo,
    content: Field::Text,
    media: AttachedMediaField,
    status: Field::Select.with_options(collection: Suggestion.statuses.keys),
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    created_at
    source
    name
    company
    account
    content
    media
    status
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    created_at
    source
    name
    company
    account
    user
    content
    media
    status
    updated_at
  ].freeze

  # So o status e editavel: nome, empresa e texto sao o que a pessoa escreveu, e o anexo veio com
  # ela. Mexer neles aqui seria reescrever o relato de outra pessoa.
  FORM_ATTRIBUTES = %i[
    status
  ].freeze

  COLLECTION_FILTERS = {
    nova: ->(resources) { resources.where(status: :nova) },
    in_app: ->(resources) { resources.where(source: :in_app) },
    public_link: ->(resources) { resources.where(source: :public_link) }
  }.freeze

  def display_resource(suggestion)
    "Sugestão ##{suggestion.id}"
  end
end
