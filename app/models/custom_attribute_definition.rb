# == Schema Information
#
# Table name: custom_attribute_definitions
#
#  id                     :bigint           not null, primary key
#  attribute_description  :text
#  attribute_display_name :string
#  attribute_display_type :integer          default("text")
#  attribute_key          :string
#  attribute_model        :integer          default("conversation_attribute")
#  attribute_values       :jsonb
#  default_value          :integer
#  regex_cue              :string
#  regex_pattern          :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint
#
# Indexes
#
#  attribute_key_model_index                         (attribute_key,attribute_model,account_id) UNIQUE
#  index_custom_attribute_definitions_on_account_id  (account_id)
#
class CustomAttributeDefinition < ApplicationRecord
  STANDARD_ATTRIBUTES = {
    :conversation => %w[status priority assignee_id inbox_id team_id display_id campaign_id labels browser_language country_code referer created_at
                        last_activity_at],
    :contact => %w[name email phone_number identifier country_code city company_name created_at last_activity_at referer blocked],
    :company => %w[name domain description contacts_count created_at updated_at last_activity_at]
  }.freeze

  # Chave i18n da descricao que CustomAttributes::AutoProvisionService grava
  # quando cria a definicao a partir de uma chave que o site mandou.
  AUTO_PROVISIONED_DESCRIPTION_KEY = 'custom_attributes.auto_provisioned.description'.freeze

  # Bloco 4.17 — origem da definicao. `nil` e a definicao anterior a coluna: nao se sabe
  # quem a criou, e gravar 'agent' nela seria afirmar o que nao se mediu (regra A4, sem
  # backfill).
  ORIGIN_AGENT = 'agent'.freeze
  ORIGIN_WEBSITE = 'website'.freeze
  ORIGINS = [ORIGIN_AGENT, ORIGIN_WEBSITE].freeze

  scope :with_attribute_model, ->(attribute_model) { attribute_model.presence && where(attribute_model: attribute_model) }
  validates :attribute_display_name, presence: true
  before_validation :normalize_attribute_fields

  validates :attribute_key,
            presence: true,
            uniqueness: { scope: [:account_id, :attribute_model] },
            format: { with: /\A[\p{L}\p{N}_.\-]+\z/, message: I18n.t('errors.custom_attribute_definition.attribute_key_format') }

  validates :attribute_display_type, presence: true
  validates :origin, inclusion: { in: ORIGINS }, allow_nil: true
  validates :attribute_model, presence: true
  validate :attribute_must_not_conflict, on: :create

  enum attribute_model: { conversation_attribute: 0, contact_attribute: 1, company_attribute: 2 }
  enum attribute_display_type: { text: 0, number: 1, currency: 2, percent: 3, link: 4, date: 5, list: 6, checkbox: 7 }

  belongs_to :account
  after_update :update_widget_pre_chat_custom_fields, unless: :company_attribute?
  after_destroy :sync_widget_pre_chat_custom_fields, unless: :company_attribute?
  after_update_commit :invalidate_filtered_unread_count_filters_update, if: :conversation_attribute_before_or_after?
  after_destroy_commit :invalidate_filtered_unread_count_filters_destroy, if: :conversation_attribute?

  # Selo de origem do painel (bloco 1.17). A comparacao e por igualdade exata
  # contra o texto traduzido — de proposito: a descricao e devolvida na API
  # exatamente como esta no banco, e o formulario de edicao a reenvia inteira.
  # Transformar o valor na leitura faria o proprio salvamento apagar o sinal.
  # Se o agente reescrever a descricao, o selo some — ele assumiu o atributo.
  def auto_provisioned_from_website?
    # Bloco 4.17: a coluna e a fonte de verdade a partir daqui. A comparacao por descricao
    # so responde pelas definicoes criadas ANTES da coluna existir — sem ela, o selo do
    # 1.17 sumiria de toda linha antiga no dia da migration.
    return origin == ORIGIN_WEBSITE if origin.present?
    return false if attribute_description.blank?

    self.class.auto_provisioned_descriptions.include?(attribute_description)
  end

  # As chaves desta conta que so aceitam escrita com origem verificada. Consulta estreita
  # de proposito: e ela que roda no caminho quente de toda escrita vinda do site.
  def self.protected_keys(account:, attribute_model:)
    where(account_id: account.id, attribute_model: attribute_model, requires_verified_origin: true)
      .pluck(:attribute_key)
  end

  def self.auto_provisioned_descriptions
    # A descricao e gravada com I18n.t no locale ativo da requisicao, entao a
    # comparacao cobre todos os locales. Lista pequena e constante em runtime.
    @auto_provisioned_descriptions ||= I18n.available_locales.filter_map do |locale|
      I18n.t(AUTO_PROVISIONED_DESCRIPTION_KEY, locale: locale, default: nil).presence
    end.uniq
  end

  private

  def normalize_attribute_fields
    self.attribute_key = attribute_key.strip if attribute_key.present?
    self.attribute_display_name = attribute_display_name.strip if attribute_display_name.present?
  end

  def sync_widget_pre_chat_custom_fields
    ::Inboxes::SyncWidgetPreChatCustomFieldsJob.perform_later(account_id, attribute_key)
  end

  def update_widget_pre_chat_custom_fields
    attrs = {
      'attribute_key' => attribute_key,
      'attribute_display_name' => attribute_display_name,
      'attribute_values' => attribute_values,
      'regex_pattern' => regex_pattern,
      'regex_cue' => regex_cue
    }
    ::Inboxes::UpdateWidgetPreChatCustomFieldsJob.perform_later(account_id, attrs)
  end

  def invalidate_filtered_unread_count_filters_update
    invalidate_filtered_unread_count_filters
  end

  def invalidate_filtered_unread_count_filters_destroy
    invalidate_filtered_unread_count_filters
  end

  def invalidate_filtered_unread_count_filters
    filters_changed = ::Conversations::UnreadCounts::FilteredCountInvalidator.new(account).custom_attribute_definition_changed!(self)
    dispatch_account_cache_invalidated if filters_changed
  end

  def dispatch_account_cache_invalidated
    Rails.configuration.dispatcher.dispatch(ACCOUNT_CACHE_INVALIDATED, Time.zone.now, account: account, cache_keys: account.cache_keys)
  end

  def conversation_attribute_before_or_after?
    conversation_attribute? || attribute_model_previously_was == 'conversation_attribute'
  end

  def attribute_must_not_conflict
    model_keys = attribute_model.to_s.delete_suffix('_attribute').to_sym
    standard_attributes = STANDARD_ATTRIBUTES[model_keys]
    return if standard_attributes.blank?
    return unless attribute_key.in?(standard_attributes)

    errors.add(:attribute_key, I18n.t('errors.custom_attribute_definition.key_conflict'))
  end
end

CustomAttributeDefinition.include_mod_with('Concerns::CustomAttributeDefinition')
