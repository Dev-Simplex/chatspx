# frozen_string_literal: true

require 'rails_helper'

# Regressão: o board SEMPRE manda `exclude_automation_type=resolved`, e o filtro
# era `where.not(funnel_stages: { automation_type: ... })`. Como a coluna é
# NULÁVEL e em SQL `NULL != 'resolved'` vale NULL (não TRUE), toda etapa SEM
# automação — "Em andamento", "Aguardando cliente", a maioria delas — sumia
# inteira da listagem. Os cards continuavam no banco e chegavam pelo websocket,
# mas desapareciam a cada recarga: "os dados não atualizam direito".
RSpec.describe 'Funnel Items exclude_automation_type', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:funnel) { Funnel.create!(account: account, name: 'Vendas') }

  let!(:aberto) { FunnelStage.create!(funnel: funnel, name: 'Aberto', position: 0, automation_type: 'open') }
  let!(:andamento) { FunnelStage.create!(funnel: funnel, name: 'Em andamento', position: 1, automation_type: nil) }
  let!(:resolvido) { FunnelStage.create!(funnel: funnel, name: 'Resolvido', position: 2, automation_type: 'resolved') }

  let!(:card_aberto) { card_in(aberto) }
  let!(:card_andamento) { card_in(andamento) }
  let!(:card_resolvido) { card_in(resolvido) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_items" }

  def card_in(stage)
    conversation = create(:conversation, account: account, inbox: inbox)
    FunnelItem.create!(funnel: funnel, funnel_stage: stage, conversation: conversation)
  end

  def ids_from(response_body)
    parsed = JSON.parse(response_body)
    (parsed.is_a?(Hash) ? parsed['payload'] : parsed).map { |item| item['id'] }
  end

  shared_examples 'mantém a etapa sem automação' do |extra_params|
    it 'devolve o card da etapa sem automação e esconde só o resolvido' do
      get base_url, params: { exclude_automation_type: 'resolved' }.merge(extra_params), headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      ids = ids_from(response.body)
      expect(ids).to include(card_andamento.id)
      expect(ids).to include(card_aberto.id)
      expect(ids).not_to include(card_resolvido.id)
    end

    it 'devolve os cards ao filtrar aquela etapa isoladamente (é o que o board faz por coluna)' do
      get base_url,
          params: { exclude_automation_type: 'resolved', stage_id: andamento.id }.merge(extra_params),
          headers: admin.create_new_auth_token

      expect(ids_from(response.body)).to eq([card_andamento.id])
    end
  end

  context 'when cursor mode is on (Kanban::FunnelItemsQueryService)' do
    before { account.enable_features!('kanban_cursor_loading') }

    it_behaves_like 'mantém a etapa sem automação', { mode: 'cursor', limit: 30 }
  end

  context 'when falling back to the legacy path' do
    it_behaves_like 'mantém a etapa sem automação', {}
  end
end
