require 'rails_helper'

# Bloco 3.01 — a UNICA edicao de `inbox_attributes` (o `:217` do plano, `:260` nesta base) declara as
# quatro chaves de uma vez. O que este spec cobre e a juncao: o `permit` e o merge raso do `#update`.
RSpec.describe 'Inbox widget configuration API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}" }

  def patch_inbox(additional_attributes)
    patch base_url,
          headers: admin.create_new_auth_token,
          params: { additional_attributes: additional_attributes },
          as: :json
  end

  def stored_attributes
    get base_url, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    response.parsed_body['additional_attributes']
  end

  describe 'PATCH with the four widget keys' do
    it 'persists widget_profile and returns it on the following GET' do
      patch_inbox(widget_profile: 'marketing')

      expect(response).to have_http_status(:success)
      expect(inbox.reload.widget_profile).to eq('marketing')
      expect(stored_attributes['widget_profile']).to eq('marketing')
    end

    it 'persists widget_appearance and returns it on the following GET' do
      patch_inbox(widget_appearance: { position: 'left' })

      expect(response).to have_http_status(:success)
      expect(inbox.reload.widget_appearance).to eq({ 'position' => 'left' })
      expect(stored_attributes['widget_appearance']).to eq({ 'position' => 'left' })
    end

    it 'persists widget_triggers and widget_tracking as whole objects' do
      patch_inbox(
        widget_triggers: { version: 1, enabled: true, triggers: [{ id: 'time_on_page', desktop: { enabled: true, value: 15 } }] },
        widget_tracking: { meta_pixel_id: '1234567890', event_map: { conversation_started: 'Lead' } }
      )

      expect(response).to have_http_status(:success)
      expect(inbox.reload.widget_triggers['triggers'].first['desktop']).to eq({ 'enabled' => true, 'value' => 15 })
      expect(inbox.widget_tracking).to eq({ 'meta_pixel_id' => '1234567890', 'event_map' => { 'conversation_started' => 'Lead' } })
    end

    it 'rejects an invalid widget_profile with 422 naming the field' do
      patch_inbox(widget_profile: 'suporte')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['attributes']).to include('widget_profile')
      # A requisicao real responde no locale da instalacao (pt_BR, config/application.rb:48) — e nao no
      # `with_locale(:en)` do rails_helper, que so envolve o exemplo. E o texto que o admin ve no dashboard.
      expect(response.parsed_body['message']).to eq('Widget profile não é um perfil de widget válido (valores aceitos: support, marketing)')
      expect(inbox.reload.widget_profile).to be_nil
    end

    it 'rejects a secret smuggled into widget_tracking with 422' do
      patch_inbox(widget_tracking: { meta_pixel_id: '123', access_token: 'EAAG-should-never-land-here' })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['attributes']).to include('widget_tracking')
      expect(response.parsed_body['message']).to include('access_token')
      expect(inbox.reload.widget_tracking).to be_nil
    end
  end

  describe 'the shallow merge of #update (inboxes_controller.rb:52-56)' do
    before do
      inbox.update!(
        widget_profile: 'marketing',
        widget_triggers: { 'version' => 1 },
        widget_tracking: { 'meta_pixel_id' => '123' },
        widget_appearance: { 'position' => 'left' }
      )
    end

    it 'a partial PATCH of one key does not wipe the other three' do
      patch_inbox(widget_triggers: { version: 2 })

      expect(response).to have_http_status(:success)
      attributes = stored_attributes
      expect(attributes['widget_triggers']).to eq({ 'version' => 2 })
      expect(attributes['widget_profile']).to eq('marketing')
      expect(attributes['widget_tracking']).to eq({ 'meta_pixel_id' => '123' })
      expect(attributes['widget_appearance']).to eq({ 'position' => 'left' })
    end

    it 'preserves keys of additional_attributes that are not ours' do
      inbox.update!(pin_mode: 'per_agent')

      patch_inbox(widget_profile: 'support')

      expect(stored_attributes['pin_mode']).to eq('per_agent')
      expect(stored_attributes['widget_profile']).to eq('support')
    end
  end

  describe 'an inbox that never heard of the four keys' do
    it 'updates unrelated fields without any of them' do
      patch base_url,
            headers: admin.create_new_auth_token,
            params: { greeting_message: 'Olá' },
            as: :json

      expect(response).to have_http_status(:success)
      expect(inbox.reload.greeting_message).to eq('Olá')
      expect(inbox.additional_attributes.keys).not_to include('widget_profile', 'widget_triggers',
                                                              'widget_tracking', 'widget_appearance')
    end
  end
end
