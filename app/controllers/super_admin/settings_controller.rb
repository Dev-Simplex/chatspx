class SuperAdmin::SettingsController < SuperAdmin::ApplicationController
  def show; end

  def refresh
    Internal::CheckNewVersionsJob.perform_now
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_to super_admin_settings_path, notice: 'Instance status refreshed'
    # rubocop:enable Rails/I18nLocaleTexts
  end

  def force_refresh
    version_file = Rails.public_path.join('version.json')
    new_version = "force-#{SecureRandom.hex(6)}"
    File.write(version_file, { version: new_version, deployed_at: Time.now.to_i }.to_json)
    # rubocop:disable Rails/I18nLocaleTexts
    redirect_to super_admin_settings_path, notice: 'Hard refresh disparado. Todos os clientes serão atualizados em até 5 minutos.'
    # rubocop:enable Rails/I18nLocaleTexts
  end
end
