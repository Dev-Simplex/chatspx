# == Schema Information
#
# Table name: channel_whatsapp
#
#  id                             :bigint           not null, primary key
#  message_templates              :jsonb
#  message_templates_last_updated :datetime
#  phone_number                   :string           not null
#  phone_number_health            :jsonb            not null
#  phone_number_health_checked_at :datetime
#  phone_number_health_error      :string
#  provider                       :string           default("default")
#  provider_config                :jsonb
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  account_id                     :integer          not null
#
# Indexes
#
#  index_channel_whatsapp_on_phone_number                    (phone_number) UNIQUE
#  index_channel_whatsapp_on_phone_number_health_checked_at  (phone_number_health_checked_at)
#

class Channel::Whatsapp < ApplicationRecord
  include Channelable
  include Reauthorizable

  self.table_name = 'channel_whatsapp'
  EDITABLE_ATTRS = [:phone_number, :provider, { provider_config: {} }].freeze

  # default at the moment is 360dialog lets change later.
  PROVIDERS = %w[default whatsapp_cloud].freeze
  before_validation :ensure_webhook_verify_token

  validates :provider, inclusion: { in: PROVIDERS }
  validates :phone_number, presence: true, uniqueness: true
  validate :validate_provider_config

  after_create :sync_templates
  after_update_commit :log_credentials_transfer, if: :saved_change_to_provider_config?
  before_destroy :teardown_webhooks
  after_commit :setup_webhooks, on: :create, if: :should_auto_setup_webhooks?

  def name
    'Whatsapp'
  end

  # Quem lê content_attributes['interactive_payload'] é o WhatsappCloudService#send_message.
  # O 360Dialog (todo provider que não seja whatsapp_cloud) ignora a chave e cai no ramo de
  # texto/anexo — o payload some sem erro.
  def supports_interactive_payload?
    provider == 'whatsapp_cloud'
  end

  def provider_service
    if provider == 'whatsapp_cloud'
      Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: self)
    else
      Whatsapp::Providers::Whatsapp360DialogService.new(whatsapp_channel: self)
    end
  end

  # Whether the pending (unsaved) provider_config change drops the embedded_signup
  # source marker, i.e. this save is an embedded signup → manual setup transfer.
  def embedded_to_manual_transfer_pending?
    before, after = provider_config_change
    before&.dig('source') == 'embedded_signup' && after['source'] != 'embedded_signup'
  end

  def mark_message_templates_updated
    # rubocop:disable Rails/SkipsModelValidations
    update_column(:message_templates_last_updated, Time.zone.now)
    # rubocop:enable Rails/SkipsModelValidations
  end

  delegate :send_message, to: :provider_service
  delegate :send_template, to: :provider_service
  delegate :sync_templates, to: :provider_service
  delegate :media_url, to: :provider_service
  delegate :api_headers, to: :provider_service
  delegate :send_typing_indicator, to: :provider_service

  def setup_webhooks
    perform_webhook_setup
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP] Webhook setup failed: #{e.message}"
    prompt_reauthorization!
  end

  private

  def ensure_webhook_verify_token
    provider_config['webhook_verify_token'] ||= SecureRandom.hex(16) if provider == 'whatsapp_cloud'
  end

  def validate_provider_config
    errors.add(:provider_config, 'Invalid Credentials') unless provider_service.validate_provider_config?
  end

  # Logs only the embedded signup → manual migration (the save drops the
  # embedded_signup source marker), so credential rotations on inboxes that are
  # already manual stay silent.
  def log_credentials_transfer
    before, after = saved_change_to_provider_config
    return unless before&.dig('source') == 'embedded_signup' && after['source'] != 'embedded_signup'

    Rails.logger.info("[WHATSAPP_EMBEDDED_TO_MANUAL] success account_id=#{account_id} channel_id=#{id}")
  end

  def perform_webhook_setup
    webhook_setup_service.perform
  end

  def webhook_setup_service
    Whatsapp::WebhookSetupService.new(self, provider_config['business_account_id'], provider_config['api_key'])
  end

  def teardown_webhooks
    Whatsapp::WebhookTeardownService.new(self).perform
  end

  def should_auto_setup_webhooks?
    # Only auto-setup webhooks for whatsapp_cloud provider with manual setup
    # Embedded signup calls setup_webhooks explicitly in EmbeddedSignupService
    provider == 'whatsapp_cloud' && provider_config['source'] != 'embedded_signup'
  end
end
