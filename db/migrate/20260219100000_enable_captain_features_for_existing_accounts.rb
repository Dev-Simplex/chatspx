class EnableCaptainFeaturesForExistingAccounts < ActiveRecord::Migration[7.0]
  FEATURE_NAMES = %w[captain_integration captain_integration_v2].freeze

  def up
    update_default_feature_flags
    enable_features_for_existing_accounts
    GlobalConfig.clear_cache
  end

  private

  def update_default_feature_flags
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config.blank?

    features = Array(config.value).map(&:dup)
    features.each do |feature|
      next unless FEATURE_NAMES.include?(feature['name'])

      feature['enabled'] = true
    end

    existing_names = features.pluck('name')
    missing = FEATURE_NAMES - existing_names

    if missing.any?
      captain_defaults = YAML.safe_load(File.read(Rails.root.join('config/features.yml')))
        .select { |feature| missing.include?(feature['name']) }
        .map { |feature| feature.slice('name', 'display_name').merge('enabled' => true) }

      features.concat(captain_defaults)
    end

    config.update!(value: features)
  end

  def enable_features_for_existing_accounts
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each { |account| account.enable_features!(*FEATURE_NAMES) }
    end
  end
end
