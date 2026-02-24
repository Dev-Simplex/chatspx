require 'rails_helper'

RSpec.describe Internal::ReconcilePlanConfigService do
  describe '#perform' do
    let(:service) { described_class.new }
    let(:premium_config_defaults) do
      YAML.safe_load(
        File.read(Rails.root.join('enterprise/config/premium_installation_config.yml'))
      ).index_by { |entry| entry['name'] }
    end

    context 'when pricing plan is community' do
      before do
        allow(ChatwootHub).to receive(:pricing_plan).and_return('community')
      end

      it 'disables the premium features for accounts' do
        account = create(:account)
        account.enable_features!('disable_branding', 'audit_logs', 'captain_integration')
        account_with_captain = create(:account)
        account_with_captain.enable_features!('captain_integration')
        disable_branding_account = create(:account)
        disable_branding_account.enable_features!('disable_branding')
        service.perform
        expect(account.reload.enabled_features.keys).not_to include('disable_branding', 'audit_logs')
        expect(account.reload.enabled_features.keys).to include('captain_integration')
        expect(account_with_captain.reload.enabled_features.keys).to include('captain_integration')
        expect(disable_branding_account.reload.enabled_features.keys).not_to include('disable_branding')
      end

      it 'creates a premium config reset warning if config was modified' do
        create(:installation_config, name: 'INSTALLATION_NAME', value: 'custom-name')
        service.perform
        expect(Redis::Alfred.get(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING)).to eq('true')
      end

      it 'will not create a premium config reset warning if config is not modified' do
        create(
          :installation_config,
          name: 'INSTALLATION_NAME',
          value: premium_config_defaults['INSTALLATION_NAME']['value']
        )
        service.perform
        expect(Redis::Alfred.get(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING)).to be_nil
      end

      it 'updates the premium configs to default' do
        create(:installation_config, name: 'INSTALLATION_NAME', value: 'custom-name')
        create(:installation_config, name: 'LOGO', value: '/custom-path/logo.svg')
        service.perform
        expect(InstallationConfig.find_by(name: 'INSTALLATION_NAME').value)
          .to eq(premium_config_defaults['INSTALLATION_NAME']['value'])
        expect(InstallationConfig.find_by(name: 'LOGO').value)
          .to eq(premium_config_defaults['LOGO']['value'])
      end
    end

    context 'when pricing plan is not community' do
      before do
        allow(ChatwootHub).to receive(:pricing_plan).and_return('enterprise')
      end

      it 'unset premium config warning on upgrade' do
        Redis::Alfred.set(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING, true)
        service.perform
        expect(Redis::Alfred.get(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING)).to be_nil
      end

      it 'does not disable the premium features for accounts' do
        account = create(:account)
        account.enable_features!('disable_branding', 'audit_logs', 'captain_integration')
        account_with_captain = create(:account)
        account_with_captain.enable_features!('captain_integration')
        disable_branding_account = create(:account)
        disable_branding_account.enable_features!('disable_branding')
        service.perform
        expect(account.reload.enabled_features.keys).to include('captain_integration', 'disable_branding', 'audit_logs')
        expect(account_with_captain.reload.enabled_features.keys).to include('captain_integration')
        expect(disable_branding_account.reload.enabled_features.keys).to include('disable_branding')
      end

      it 'does not update the LOGO config' do
        create(:installation_config, name: 'INSTALLATION_NAME', value: 'custom-name')
        create(:installation_config, name: 'LOGO', value: '/custom-path/logo.svg')
        service.perform
        expect(InstallationConfig.find_by(name: 'INSTALLATION_NAME').value).to eq('custom-name')
        expect(InstallationConfig.find_by(name: 'LOGO').value).to eq('/custom-path/logo.svg')
      end
    end
  end
end
