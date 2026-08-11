# frozen_string_literal: true

require 'rails_helper'

# Kanban tempo real (Fase 2) — card entra e sai do board sem F5.
#
# Antes: cartão de tarefa criado e card apagado não disparavam evento nenhum, e
# bulk move disparava UM evento POR CARD (50 cards = 50 jobs na fila :critical).
RSpec.describe 'Funnel Items realtime', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:team) { create(:team, account: account) }
  let(:funnel) { Funnel.create!(account: account, name: 'Time X', team_id: team.id) }
  let(:stage_a) { FunnelStage.create!(funnel: funnel, name: 'Abertos', position: 0) }
  let(:stage_b) { FunnelStage.create!(funnel: funnel, name: 'Em andamento', position: 1) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, team: team) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/funnels/#{funnel.id}/funnel_items" }

  before do
    team.add_members([agent.id])
    create(:inbox_member, inbox: inbox, user: agent)
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original
  end

  describe 'POST (cartão de tarefa)' do
    it 'dispara funnel_item.created' do
      post base_url,
           params: { funnel_stage_id: stage_a.id, title: 'Ligar para o cliente' },
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with(Events::Types::FUNNEL_ITEM_CREATED, anything, hash_including(:funnel_item))
    end

    it 'não dispara funnel_item.created para card de CONVERSA (viria duplicado com o moved)' do
      post base_url,
           params: { funnel_stage_id: stage_a.id, conversation_id: conversation.display_id },
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
        .with(Events::Types::FUNNEL_ITEM_CREATED, anything, anything)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with(Events::Types::FUNNEL_ITEM_MOVED, anything, anything)
    end
  end

  describe 'DELETE' do
    it 'dispara funnel_item.deleted com os ids capturados antes do destroy' do
      item = FunnelItem.create!(funnel: funnel, funnel_stage: stage_a, conversation: conversation)

      delete "#{base_url}/#{item.id}", headers: agent.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
        Events::Types::FUNNEL_ITEM_DELETED,
        anything,
        hash_including(item: { id: item.id, funnel_id: funnel.id, funnel_stage_id: stage_a.id })
      )
      expect(FunnelItem.exists?(item.id)).to be(false)
    end
  end

  describe 'POST bulk_move' do
    let!(:conversations) { create_list(:conversation, 3, account: account, inbox: inbox, team: team) }

    it 'dispara UM evento agregado e nenhum move individual' do
      post "#{base_url}/bulk_move",
           params: { stage_id: stage_b.id, conversation_ids: conversations.map(&:id) },
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with(Events::Types::FUNNEL_ITEMS_BULK_MOVED, anything, hash_including(:funnel, :item_ids)).once
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
        .with(Events::Types::FUNNEL_ITEM_MOVED, anything, anything)
    end

    it 'não emite evento quando nada foi movido' do
      post "#{base_url}/bulk_move",
           params: { stage_id: stage_b.id, conversation_ids: [] },
           headers: agent.create_new_auth_token

      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
        .with(Events::Types::FUNNEL_ITEMS_BULK_MOVED, anything, anything)
    end
  end

  describe 'kill switch KANBAN_REALTIME_ENABLED=false' do
    it 'cala os eventos sem quebrar a ação' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('KANBAN_REALTIME_ENABLED', 'true').and_return('false')

      post base_url,
           params: { funnel_stage_id: stage_a.id, title: 'Tarefa muda' },
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(funnel.funnel_items.tasks.count).to eq(1)
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
        .with(Events::Types::FUNNEL_ITEM_CREATED, anything, anything)
    end
  end
end
