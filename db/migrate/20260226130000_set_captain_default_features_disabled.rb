class SetCaptainDefaultFeaturesDisabled < ActiveRecord::Migration[7.0]
  FEATURE_NAMES = %w[captain_integration captain_integration_v2].freeze

  def up
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config.blank?

    features = Array(config.value).map(&:dup)
    features.each do |feature|
      next unless FEATURE_NAMES.include?(feature['name'])

      feature['enabled'] = false
    end

    append_missing_features(features)
    config.update!(value: features)
    GlobalConfig.clear_cache
  end

  def down
    # Intentionally no-op: avoid re-enabling Captain by default on rollback.
  end

  private

  def append_missing_features(features)
    existing_names = features.pluck('name')
    missing = FEATURE_NAMES - existing_names
    return if missing.empty?

    captain_defaults = YAML.safe_load(File.read(Rails.root.join('config/features.yml')))
                           .select { |feature| missing.include?(feature['name']) }
                           .map { |feature| feature.slice('name', 'display_name').merge('enabled' => false) }

    features.concat(captain_defaults)
  end
end
