# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Funnel templates + form config (Kanban v2 / Fase 8)', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/funnels" }

  describe 'GET templates' do
    it 'seeds and lists the built-in templates' do
      get "#{base}/templates", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      slugs = response.parsed_body.map { |t| t['slug'] }
      expect(slugs).to include('support', 'sales')
      expect(FunnelTemplate.count).to be >= 4
    end

    it 'requires authentication' do
      get "#{base}/templates"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST create_from_template' do
    it 'creates a funnel with the template stages + custom fields' do
      template = Kanban::EnsureFunnelTemplatesService.new.perform.find { |t| t.slug == 'sales' }

      expect do
        post "#{base}/create_from_template",
             params: { template_id: template.id, name: 'Meu funil de vendas' },
             headers: agent.create_new_auth_token, as: :json
      end.to change(account.funnels, :count).by(1)

      expect(response).to have_http_status(:created)
      funnel = account.funnels.find(response.parsed_body['id'])
      expect(funnel.name).to eq('Meu funil de vendas')
      expect(funnel.funnel_stages.count).to eq(4)
      expect(funnel.funnel_custom_fields.pluck(:key)).to include('valor')
    end
  end

  describe 'POST form (enable public form)' do
    let(:funnel) { Funnel.create!(account: account, name: 'Vendas') }

    it 'mints a token + URL and enables the form' do
      post "#{base}/#{funnel.id}/form",
           params: { enabled: true, title: 'Fale conosco' },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['form_enabled']).to be(true)
      expect(response.parsed_body['form_token']).to be_present
      expect(response.parsed_body['form_url']).to include(response.parsed_body['form_token'])
      expect(funnel.reload.public_form_enabled?).to be(true)
    end

    it 'disabling keeps the token but turns the form off' do
      funnel.update!(settings: { 'form_enabled' => true, 'form_token' => 'keep-me' })

      post "#{base}/#{funnel.id}/form",
           params: { enabled: false },
           headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['form_enabled']).to be(false)
      expect(funnel.reload.form_token).to eq('keep-me')
    end
  end
end
