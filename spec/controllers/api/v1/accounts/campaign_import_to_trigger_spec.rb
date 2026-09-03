# frozen_string_literal: true

require 'rails_helper'

# 4.22 — a porta HTTP da rampa. O cálculo está no service; aqui ficam autorização,
# escopo de conta e a forma da resposta que a tela consome.
RSpec.describe 'Api::V1::Accounts::CampaignsController#import_to_trigger', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }
  let!(:campanha) do
    create(:campaign, account: account, inbox: inbox, campaign_type: :ongoing,
                      enabled: true, trigger_rules: { 'url' => 'https://site.com', 'time_on_page' => 12 })
  end

  # A rota deste controller resolve por `display_id`, nao por `id` (campaigns_controller
  # :64). Usar o `id` devolve 404 e o teste passaria a medir o proprio engano.
  def importar(como: administrator, alvo: campanha)
    post "/api/v1/accounts/#{account.id}/campaigns/#{alvo.display_id}/import_to_trigger",
         headers: como.create_new_auth_token
  end

  describe 'autorização' do
    it 'recusa requisição sem autenticação' do
      post "/api/v1/accounts/#{account.id}/campaigns/#{campanha.display_id}/import_to_trigger"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'recusa agente — importar desativa campanha e reescreve a inbox' do
      importar(como: agente)

      expect(response).to have_http_status(:unauthorized)
      expect(campanha.reload.enabled).to be(true)
    end
  end

  describe 'importação' do
    it 'devolve o gatilho criado e a campanha já desativada' do
      importar

      expect(response).to have_http_status(:success)
      corpo = response.parsed_body
      expect(corpo['widget_triggers']['enabled']).to be(true)
      expect(corpo['campaign']['enabled']).to be(false)
      expect(campanha.reload.enabled).to be(false)
    end

    it 'recusa com 422 e mensagem quando a campanha não é de chat ao vivo' do
      whatsapp = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
      outra = create(:campaign, account: account, inbox: whatsapp.inbox, campaign_type: :one_off, enabled: true)

      importar(alvo: outra)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to match(/chat ao vivo/)
      expect(outra.reload.enabled).to be(true)
    end

    # `display_id` e sequencial POR CONTA, entao a campanha alheia e a minha nascem as duas
    # com display_id 1. Um teste ingenuo pediria "1", o controller acharia a MINHA, devolveria
    # 200 e o exemplo passaria a medir o proprio engano. Aqui a conta alheia recebe tres
    # campanhas para que a terceira tenha um display_id que a minha conta nao possui.
    it 'não alcança campanha de outra conta' do
      outra_conta = create(:account)
      outro_widget = create(:channel_widget, account: outra_conta)
      alheias = Array.new(3) do
        create(:campaign, account: outra_conta, inbox: outro_widget.inbox,
                          campaign_type: :ongoing, enabled: true)
      end
      alheia = alheias.last
      expect(account.campaigns.where(display_id: alheia.display_id)).to be_empty

      importar(alvo: alheia)

      expect(response).to have_http_status(:not_found)
      expect(alheia.reload.enabled).to be(true)
    end
  end
end
