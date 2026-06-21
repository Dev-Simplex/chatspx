require 'rails_helper'

RSpec.describe Users::UiSettingUpdateService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }

  describe '#perform' do
    context 'when ui_settings is empty' do
      it 'merges new mobile-only keys preserving an empty hash' do
        described_class.new(user: user, params: { theme_preference: 'dark' }).perform
        expect(user.reload.ui_settings).to eq({ 'theme_preference' => 'dark' })
      end
    end

    context 'when ui_settings already contains Vue dashboard keys' do
      before do
        user.update!(ui_settings: {
                       'conversations_filter_by' => { 'name' => 'open', 'i18n_key' => 'open' },
                       'display_rich_content_editor' => true
                     })
      end

      it 'merges mobile keys without overwriting existing Vue keys' do
        result = described_class.new(
          user: user,
          params: { wallpaper_key: 'forest_dawn', theme_preference: 'system', font_scale: 1.1 }
        ).perform

        expect(result).to be true
        merged = user.reload.ui_settings
        expect(merged['conversations_filter_by']).to eq({ 'name' => 'open', 'i18n_key' => 'open' })
        expect(merged['display_rich_content_editor']).to be true
        expect(merged['wallpaper_key']).to eq('forest_dawn')
        expect(merged['theme_preference']).to eq('system')
        expect(merged['font_scale']).to eq(1.1)
      end

      it 'only updates the keys provided, leaving previously-set mobile keys intact' do
        user.update!(ui_settings: user.ui_settings.merge(
          'wallpaper_key' => 'forest_dawn',
          'theme_preference' => 'dark',
          'font_scale' => 1.0
        ))

        described_class.new(user: user, params: { font_scale: 1.25 }).perform

        merged = user.reload.ui_settings
        expect(merged['wallpaper_key']).to eq('forest_dawn')
        expect(merged['theme_preference']).to eq('dark')
        expect(merged['font_scale']).to eq(1.25)
        expect(merged['display_rich_content_editor']).to be true
      end
    end

    context 'when keys outside the allow-list are provided' do
      it 'silently drops them and does not touch ui_settings for those keys' do
        user.update!(ui_settings: { 'display_rich_content_editor' => true })

        described_class.new(
          user: user,
          params: { display_rich_content_editor: false, theme_preference: 'light' }
        ).perform

        merged = user.reload.ui_settings
        expect(merged['display_rich_content_editor']).to be true
        expect(merged['theme_preference']).to eq('light')
      end
    end

    context 'when theme_preference is invalid' do
      it 'returns false and exposes a validation error' do
        service = described_class.new(user: user, params: { theme_preference: 'neon' })
        expect(service.perform).to be false
        expect(service.errors).to include(a_string_matching(/theme_preference must be one of/))
        expect(user.reload.ui_settings).to be_blank
      end
    end

    context 'when font_scale is out of range' do
      it 'rejects values below the minimum' do
        service = described_class.new(user: user, params: { font_scale: 0.5 })
        expect(service.perform).to be false
        expect(service.errors).to include(a_string_matching(/font_scale must be between/))
      end

      it 'rejects values above the maximum' do
        service = described_class.new(user: user, params: { font_scale: 2.0 })
        expect(service.perform).to be false
        expect(service.errors).to include(a_string_matching(/font_scale must be between/))
      end

      it 'rejects non-numeric values' do
        service = described_class.new(user: user, params: { font_scale: 'huge' })
        expect(service.perform).to be false
        expect(service.errors).to include(a_string_matching(/numeric/))
      end

      it 'accepts the boundary values' do
        expect(described_class.new(user: user, params: { font_scale: 0.85 }).perform).to be true
        expect(described_class.new(user: user, params: { font_scale: 1.30 }).perform).to be true
        expect(user.reload.ui_settings['font_scale']).to eq(1.30)
      end
    end

    context 'when wallpaper_key is too long' do
      it 'rejects strings longer than 64 chars' do
        service = described_class.new(user: user, params: { wallpaper_key: 'x' * 65 })
        expect(service.perform).to be false
        expect(service.errors).to include(a_string_matching(/wallpaper_key must be at most/))
      end

      it 'accepts a 64-character string' do
        service = described_class.new(user: user, params: { wallpaper_key: 'x' * 64 })
        expect(service.perform).to be true
      end
    end

    context 'when no allowed keys are present' do
      it 'returns true and does not touch the database' do
        user.update!(ui_settings: { 'display_rich_content_editor' => true })

        expect do
          described_class.new(user: user, params: { foo: 'bar' }).perform
        end.not_to(change { user.reload.ui_settings })
      end
    end
  end
end
