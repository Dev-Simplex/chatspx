# == Schema Information
#
# Table name: account_integrations
#
#  id         :bigint           not null, primary key
#  enabled    :boolean          default(FALSE), not null
#  provider   :string           not null
#  settings   :text
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_account_integrations_on_account_id               (account_id)
#  index_account_integrations_on_account_id_and_provider  (account_id,provider) UNIQUE
#
class AccountIntegration < ApplicationRecord
  SUPPORTED_PROVIDERS = %w[vista google].freeze

  # Secret keys are masked (suffix-only) in API responses, matching the LLM key pattern.
  SECRET_KEYS = %w[vista_api_key google_maps_key].freeze

  belongs_to :account

  # `settings` is a Hash of per-provider credentials/config. It is stored in a TEXT
  # column and serialized as JSON so it can be transparently encrypted: when AR
  # Encryption keys are present (Chatwoot.encryption_configured?) the column is
  # encrypted at rest; otherwise it falls back to plaintext JSON so the feature keeps
  # working on unencrypted installs. `support_unencrypted_data` (config/application.rb)
  # lets encrypted reads coexist with any legacy plaintext rows after keys are added.
  serialize :settings, coder: JSON, type: Hash
  encrypts :settings if Chatwoot.encryption_configured?

  validates :provider, presence: true,
                       inclusion: { in: SUPPORTED_PROVIDERS },
                       uniqueness: { scope: :account_id }

  # Instance helper: fetch a single setting value (string-key tolerant).
  def setting(key)
    (settings || {})[key.to_s]
  end

  # Class helper: settings Hash for an account + provider, or {} when absent.
  def self.settings_for(account, provider)
    find_by(account_id: account.id, provider: provider.to_s)&.settings || {}
  end

  # API-safe representation of settings with secret values masked.
  def masked_settings
    (settings || {}).each_with_object({}) do |(key, value), acc|
      acc[key.to_s] = SECRET_KEYS.include?(key.to_s) ? self.class.mask_secret(value) : value
    end
  end

  # Suffix-only masking, same shape as the LLM API key masking.
  def self.mask_secret(value)
    str = value.to_s
    return nil if str.blank?
    return '*' * str.length if str.length <= 8

    "#{str[0..3]}#{'*' * (str.length - 8)}#{str[-4..]}"
  end
end
