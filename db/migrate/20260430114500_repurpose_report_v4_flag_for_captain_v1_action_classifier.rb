class RepurposeReportV4FlagForCaptainV1ActionClassifier < ActiveRecord::Migration[7.1]
  def up
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config&.value.blank?

    config.value = config.value.reject { |feature| feature['name'] == 'report_v4' }
    config.save!
    GlobalConfig.clear_cache
  end
end
