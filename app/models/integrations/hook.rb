# == Schema Information
#
# Table name: integrations_hooks
#
#  id           :bigint           not null, primary key
#  access_token :string
#  hook_type    :integer          default("account")
#  settings     :jsonb
#  status       :integer          default("enabled")
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :integer
#  app_id       :string
#  inbox_id     :integer
#  reference_id :string
#
class Integrations::Hook < ApplicationRecord
  include Reauthorizable

  CAPTADOR_SECRET_PREFIX = 'encrypted:v1:'.freeze

  attr_readonly :app_id, :account_id, :inbox_id, :hook_type
  before_validation :ensure_hook_type
  before_validation :encrypt_captador_shared_secret
  after_create :trigger_setup_if_crm

  # TODO: Remove guard once encryption keys become mandatory (target 3-4 releases out).
  encrypts :access_token, deterministic: true if Chatwoot.encryption_configured?

  validates :account_id, presence: true
  validates :app_id, presence: true
  validates :inbox_id, presence: true, if: -> { hook_type == 'inbox' }
  validate :validate_settings_json_schema
  validate :ensure_feature_enabled
  validates :app_id, uniqueness: { scope: [:account_id], unless: -> { app.present? && app.params[:allow_multiple_hooks].present? } }

  # TODO: This seems to be only used for slack at the moment
  # We can add a validator when storing the integration settings and toggle this in future
  enum status: { disabled: 0, enabled: 1 }

  belongs_to :account
  belongs_to :inbox, optional: true
  has_secure_token :access_token

  enum hook_type: { account: 0, inbox: 1 }

  scope :account_hooks, -> { where(hook_type: 'account') }
  scope :inbox_hooks, -> { where(hook_type: 'inbox') }

  def app
    @app ||= Integrations::App.find(id: app_id)
  end

  def slack?
    app_id == 'slack'
  end

  def dialogflow?
    app_id == 'dialogflow'
  end

  def notion?
    app_id == 'notion'
  end

  # O segredo do Captador vive dentro do JSONB legado. Mantemos o formato sem migration, mas o
  # valor fica cifrado com a chave da instalação; linhas antigas são recifradas no primeiro uso.
  def captador_shared_secret
    value = settings.to_h.stringify_keys['shared_secret'].to_s
    return value unless app_id == 'captador'
    return decrypt_captador_shared_secret(value) if value.start_with?(CAPTADOR_SECRET_PREFIX)

    persist_encrypted_captador_shared_secret(value) if value.present? && persisted?
    value
  end

  def captador_shared_secret_configured?
    captador_shared_secret.present?
  end

  def disable
    update(status: 'disabled')
  end

  def process_event(_event)
    # OpenAI integration migrated to Captain::EditorService
    # Other integrations (slack, dialogflow, etc.) handled via HookJob
    { error: 'No processor found' }
  end

  def feature_allowed?
    return true if app.blank?

    flag = app.params[:feature_flag]
    return true unless flag

    account.feature_enabled?(flag)
  end

  private

  def encrypt_captador_shared_secret
    return unless app_id == 'captador'

    current = settings.to_h.stringify_keys
    secret = current['shared_secret'].to_s
    return if secret.blank? || secret.start_with?(CAPTADOR_SECRET_PREFIX)

    self.settings = current.merge('shared_secret' => encrypt_captador_shared_secret_value(secret))
  end

  def persist_encrypted_captador_shared_secret(secret)
    encrypted_settings = settings.to_h.stringify_keys.merge('shared_secret' => encrypt_captador_shared_secret_value(secret))
    update_column(:settings, encrypted_settings) # rubocop:disable Rails/SkipsModelValidations -- lazy backfill sem migration
    self.settings = encrypted_settings
  end

  def encrypt_captador_shared_secret_value(secret)
    CAPTADOR_SECRET_PREFIX + captador_secret_encryptor.encrypt_and_sign(secret)
  end

  def decrypt_captador_shared_secret(value)
    captador_secret_encryptor.decrypt_and_verify(value.delete_prefix(CAPTADOR_SECRET_PREFIX))
  end

  def captador_secret_encryptor
    key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key('spx/captador/shared_secret', 32)
    ActiveSupport::MessageEncryptor.new(key)
  end

  def ensure_feature_enabled
    errors.add(:feature_flag, 'Feature not enabled') unless feature_allowed?
  end

  def ensure_hook_type
    self.hook_type = app.params[:hook_type] if app.present?
  end

  def validate_settings_json_schema
    return if app.blank? || app.params[:settings_json_schema].blank?

    errors.add(:settings, ': Invalid settings data') unless JSONSchemer.schema(app.params[:settings_json_schema]).valid?(settings)
  end

  def trigger_setup_if_crm
    # we need setup services to create data prerequisite to functioning of the integration
    # in case of Leadsquared, we need to create a custom activity type for capturing conversations and transcripts
    # https://apidocs.leadsquared.com/create-new-activity-type-api/
    return unless crm_integration?

    ::Crm::SetupJob.perform_later(id)
  end

  def crm_integration?
    %w[leadsquared captador].include?(app_id)
  end
end
