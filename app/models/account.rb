# == Schema Information
#
# Table name: accounts
#
#  id                    :integer          not null, primary key
#  auto_resolve_duration :integer
#  custom_attributes     :jsonb
#  domain                :string(100)
#  feature_flags         :bigint           default(0), not null
#  internal_attributes   :jsonb            not null
#  limits                :jsonb
#  locale                :integer          default("en")
#  name                  :string           not null
#  settings              :jsonb
#  status                :integer          default("active")
#  support_email         :string(100)
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
# Indexes
#
#  index_accounts_on_status  (status)
#

class Account < ApplicationRecord # rubocop:disable Metrics/ClassLength
  # used for single column multi flags
  include FlagShihTzu
  include Reportable
  include Featurable
  include CacheKeys
  include CaptainFeaturable
  include AccountEmailRateLimitable

  SETTINGS_PARAMS_SCHEMA = {
    'type': 'object',
    'properties':
      {
        'auto_resolve_after': { 'type': %w[integer null], 'minimum': 10, 'maximum': 1_439_856 },
        'auto_resolve_message': { 'type': %w[string null] },
        'auto_resolve_ignore_waiting': { 'type': %w[boolean null] },
        'audio_transcriptions': { 'type': %w[boolean null] },
        'auto_resolve_label': { 'type': %w[string null] },
        'keep_pending_on_bot_failure': { 'type': %w[boolean null] },
        'resolve_assignment_gate': { 'type': %w[boolean null] },
        'takeover_request_gate': { 'type': %w[boolean null] },
        'captain_auto_resolve_mode': { 'type': %w[string null], 'enum': ['evaluated', 'legacy', 'disabled', nil] },
        'reply_assignment_gate': { 'type': %w[boolean null] },
        'orphan_retriage_after': { 'type': %w[integer null], 'minimum': 5, 'maximum': 10_080 },
        'template_reply_routing': {
          'type': %w[object null],
          'properties': {
            'enabled': { 'type': %w[boolean null] },
            'rmkt_label_prefix': { 'type': %w[string null] },
            'rmkt_assistant_id': { 'type': %w[integer null] }
          },
          'additionalProperties': false
        },
        'contact_invite': {
          'type': %w[object null],
          'properties': {
            'enabled': { 'type': %w[boolean null] },
            'template_name': { 'type': %w[string null] },
            'referral_template_name': { 'type': %w[string null] },
            'language': { 'type': %w[string null] },
            'cooldown_hours': { 'type': %w[integer null], 'minimum': 1, 'maximum': 720 },
            'referral_label': { 'type': %w[string null] }
          },
          'additionalProperties': false
        },
        'conversation_required_attributes': {
          'type': %w[array null],
          'items': { 'type': 'string' }
        },
        'captain_models': {
          'type': %w[object null],
          'properties': {
            'editor': { 'type': %w[string null] },
            'assistant': { 'type': %w[string null] },
            'copilot': { 'type': %w[string null] },
            'label_suggestion': { 'type': %w[string null] },
            'audio_transcription': { 'type': %w[string null] },
            'help_center_search': { 'type': %w[string null] }
          },
          'additionalProperties': false
        },
        'captain_features': {
          'type': %w[object null],
          'properties': {
            'editor': { 'type': %w[boolean null] },
            'assistant': { 'type': %w[boolean null] },
            'copilot': { 'type': %w[boolean null] },
            'label_suggestion': { 'type': %w[boolean null] },
            'audio_transcription': { 'type': %w[boolean null] },
            'help_center_search': { 'type': %w[boolean null] }
          },
          'additionalProperties': false
        }
      },
    'required': [],
    'additionalProperties': true
  }.to_json.freeze

  DEFAULT_QUERY_SETTING = {
    flag_query_mode: :bit_operator,
    check_for_column: false
  }.freeze

  validates :name, presence: true
  validates :domain, length: { maximum: 100 }
  validates_with JsonSchemaValidator,
                 schema: SETTINGS_PARAMS_SCHEMA,
                 attribute_resolver: ->(record) { record.settings }
  validate :validate_reporting_timezone

  store_accessor :settings, :auto_resolve_after, :auto_resolve_message, :auto_resolve_ignore_waiting

  store_accessor :settings, :audio_transcriptions, :auto_resolve_label
  store_accessor :settings, :chat_wallpaper_url, :show_dashboard_kpi_strip
  store_accessor :settings, :onboarding_completed_steps, :onboarding_dismissed
  store_accessor :settings, :openai_api_key, :openai_model_default, :openai_model_advanced, :openai_model_vision
  store_accessor :settings, :captain_models, :captain_features
  store_accessor :settings, :reporting_timezone
  store_accessor :settings, :keep_pending_on_bot_failure
  store_accessor :settings, :captain_auto_resolve_mode
  store_accessor :settings, :reply_assignment_gate, :orphan_retriage_after
  store_accessor :settings, :template_reply_routing
  store_accessor :settings, :contact_invite
  store_accessor :settings, :resolve_assignment_gate
  # Modo "só troca de mãos via pedido aprovado" (D1). Independente do
  # reply_assignment_gate de propósito: acoplar no backend seria surpresa.
  # NÃO vai em features.yml — o bitmask bigint já estourou os 63 bits.
  store_accessor :settings, :takeover_request_gate
  include AccountCaptainAutoResolve

  has_many :account_users, dependent: :destroy_async
  has_many :agent_bot_inboxes, dependent: :destroy_async
  has_many :agent_bots, dependent: :destroy_async
  has_many :api_channels, dependent: :destroy_async, class_name: '::Channel::Api'
  has_many :articles, dependent: :destroy_async, class_name: '::Article'
  has_many :assignment_policies, dependent: :destroy_async
  has_many :automation_rules, dependent: :destroy_async
  has_many :macros, dependent: :destroy_async
  has_many :flows, dependent: :destroy_async
  has_many :campaigns, dependent: :destroy_async
  has_many :canned_responses, dependent: :destroy_async
  has_many :categories, dependent: :destroy_async, class_name: '::Category'
  has_many :contacts, dependent: :destroy_async
  has_many :conversations, dependent: :destroy_async
  has_many :conversation_takeover_requests, dependent: :destroy_async
  has_many :csat_survey_responses, dependent: :destroy_async
  has_many :nps_responses, dependent: :destroy_async
  has_many :report_pdf_exports, dependent: :destroy_async
  has_many :attachment_bulk_downloads, dependent: :destroy_async
  has_many :custom_attribute_definitions, dependent: :destroy_async
  has_many :custom_filters, dependent: :destroy_async
  has_many :dashboard_apps, dependent: :destroy_async
  has_many :data_imports, dependent: :destroy_async
  has_many :email_channels, dependent: :destroy_async, class_name: '::Channel::Email'
  has_many :facebook_pages, dependent: :destroy_async, class_name: '::Channel::FacebookPage'
  has_many :instagram_channels, dependent: :destroy_async, class_name: '::Channel::Instagram'
  has_many :tiktok_channels, dependent: :destroy_async, class_name: '::Channel::Tiktok'
  has_many :hooks, dependent: :destroy_async, class_name: 'Integrations::Hook'
  has_many :inboxes, dependent: :destroy_async
  has_many :labels, dependent: :destroy_async
  has_many :line_channels, dependent: :destroy_async, class_name: '::Channel::Line'
  has_many :mentions, dependent: :destroy_async
  has_many :messages, dependent: :destroy_async
  has_many :notes, dependent: :destroy_async
  has_many :notification_settings, dependent: :destroy_async
  has_many :notifications, dependent: :destroy_async
  has_many :portals, dependent: :destroy_async, class_name: '::Portal'
  has_many :sms_channels, dependent: :destroy_async, class_name: '::Channel::Sms'
  has_many :teams, dependent: :destroy_async
  has_many :telegram_channels, dependent: :destroy_async, class_name: '::Channel::Telegram'
  has_many :twilio_sms, dependent: :destroy_async, class_name: '::Channel::TwilioSms'
  has_many :twitter_profiles, dependent: :destroy_async, class_name: '::Channel::TwitterProfile'
  has_many :users, through: :account_users
  has_many :web_widgets, dependent: :destroy_async, class_name: '::Channel::WebWidget'
  has_many :webhooks, dependent: :destroy_async
  has_many :whatsapp_channels, dependent: :destroy_async, class_name: '::Channel::Whatsapp'
  has_many :working_hours, dependent: :destroy_async
  has_many :funnels, dependent: :destroy
  has_many :funnel_views, dependent: :destroy
  has_many :message_sequences, dependent: :destroy
  has_many :internal_channels, dependent: :destroy_async

  has_one_attached :contacts_export
  has_one_attached :chat_wallpaper_image

  enum :locale, LANGUAGES_CONFIG.map { |key, val| [val[:iso_639_1_code], key] }.to_h, prefix: true
  enum :status, { active: 0, suspended: 1 }

  scope :with_auto_resolve, -> { where("(settings ->> 'auto_resolve_after')::int IS NOT NULL") }
  scope :with_reply_assignment_gate, -> { where("(settings ->> 'reply_assignment_gate')::boolean IS TRUE") }

  before_validation :validate_limit_keys
  after_create_commit :notify_creation
  after_create :create_default_funnel
  after_destroy :remove_account_sequences

  def agents
    users.where(account_users: { role: :agent })
  end

  def administrators
    users.where(account_users: { role: :administrator })
  end

  def reply_assignment_gate_enabled?
    ActiveModel::Type::Boolean.new.cast(reply_assignment_gate) || false
  end

  # Gate do motor Flow (F1). NÃO usa o bitmask de features (`feature_flags` já está no
  # limite do bigint no ChatSPX — 66 features). Guardado em internal_attributes, ligado
  # pelo admin/cutover após validar o backfill. Mutuamente exclusivo com o motor
  # AutomationRule (ver AutomationRuleListener#run_engine).
  def flows_engine_enabled?
    ActiveModel::Type::Boolean.new.cast(internal_attributes['flows_engine_enabled']) || false
  end

  def all_conversation_tags
    ActsAsTaggableOn::Tag.joins(:taggings)
                         .where(taggings: { context: 'labels', taggable_type: 'Conversation' })
                         .where(taggings: { taggable_id: conversations.select(:id) })
                         .distinct.pluck(:name)
  end

  def webhook_data
    {
      id: id,
      name: name
    }
  end

  def inbound_email_domain
    domain.presence || GlobalConfig.get('MAILER_INBOUND_EMAIL_DOMAIN')['MAILER_INBOUND_EMAIL_DOMAIN'] || ENV.fetch('MAILER_INBOUND_EMAIL_DOMAIN',
                                                                                                                   false)
  end

  def support_email
    super.presence || ENV.fetch('MAILER_SENDER_EMAIL') { GlobalConfig.get('MAILER_SUPPORT_EMAIL')['MAILER_SUPPORT_EMAIL'] }
  end

  def usage_limits
    {
      agents: ChatwootApp.max_limit.to_i,
      inboxes: ChatwootApp.max_limit.to_i
    }
  end

  def locale_english_name
    # the locale can also be something like pt_BR, en_US, fr_FR, etc.
    # the format is `<locale_code>_<country_code>`
    # we need to extract the language code from the locale
    account_locale = locale&.split('_')&.first
    ISO_639.find(account_locale)&.english_name&.downcase || 'english'
  end

  # "Atribuição obrigatória" mode: when enabled, only the assignee can resolve a
  # conversation manually. Stored as a JSONB setting flag.
  def resolve_assignment_gate_enabled?
    ActiveModel::Type::Boolean.new.cast(resolve_assignment_gate) || false
  end

  # D1 — "o pedido é o único caminho": com o modo ligado, conversa de dono humano
  # só troca de mãos via pedido aprovado ou por admin. DESLIGADO por padrão: o
  # guard é no-op enquanto isto for false, então quem não ligar não vê diferença.
  def takeover_request_gate_enabled?
    ActiveModel::Type::Boolean.new.cast(takeover_request_gate) || false
  end

  private

  def create_default_funnel
    Kanban::CreateDefaultFunnelService.new(account: self).perform
  rescue StandardError => e
    Rails.logger.error "Error creating default funnel for account #{id}: #{e.message}"
  end

  def notify_creation
    Rails.configuration.dispatcher.dispatch(ACCOUNT_CREATED, Time.zone.now, account: self)
  end

  trigger.after(:insert).for_each(:row) do
    "execute format('create sequence IF NOT EXISTS conv_dpid_seq_%s', NEW.id);"
  end

  trigger.name('camp_dpid_before_insert').after(:insert).for_each(:row) do
    "execute format('create sequence IF NOT EXISTS camp_dpid_seq_%s', NEW.id);"
  end

  def validate_limit_keys
    # method overridden in enterprise module
  end

  def validate_reporting_timezone
    return if reporting_timezone.blank? || ActiveSupport::TimeZone[reporting_timezone].present?

    errors.add(:reporting_timezone, I18n.t('errors.account.reporting_timezone.invalid'))
  end

  def remove_account_sequences
    ActiveRecord::Base.connection.exec_query("drop sequence IF EXISTS camp_dpid_seq_#{id}")
    ActiveRecord::Base.connection.exec_query("drop sequence IF EXISTS conv_dpid_seq_#{id}")
  end
end

Account.prepend_mod_with('Account')
Account.prepend_mod_with('Account::PlanUsageAndLimits')
Account.include_mod_with('Concerns::Account')
Account.include_mod_with('Audit::Account')
