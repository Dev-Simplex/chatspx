class RepurposeResponseBotFlagForCustomTools < ActiveRecord::Migration[7.1]
  def up
    # Remove the stale response_bot entry from ACCOUNT_LEVEL_FEATURE_DEFAULTS.
    # ConfigLoader only adds new flags; it never removes renamed ones.
    # Leaving it would cause NoMethodError in enable_default_features when
    # creating new accounts (feature_response_bot= no longer exists).
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config&.value.blank?

    config.value = config.value.reject { |f| f['name'] == 'response_bot' }
    config.save!
    GlobalConfig.clear_cache
  end
end
