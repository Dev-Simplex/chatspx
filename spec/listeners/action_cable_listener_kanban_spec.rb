# frozen_string_literal: true

require 'rails_helper'

# Kanban tempo real (Fase 1.4) — o alcance do broadcast do board tem que espelhar
# a FunnelPolicy. Antes ia para `account.users`, ou seja, TODO mundo da conta:
# medido no staging, um funil de um time vazio mandava nome/telefone de contato
# para 16 pessoas que nem conseguem abrir o funil. Com o payload engordado da
# Fase 1 isso virou vazamento de verdade.
describe ActionCableListener do
  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:team) { create(:team, account: account) }
  let!(:team_agent) { create(:user, account: account, role: :agent) }
  let!(:outsider) { create(:user, account: account, role: :agent) }
  let!(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  let(:team_funnel) { Funnel.create!(account: account, name: 'Vendas', team_id: team.id) }
  let(:general_funnel) { Funnel.create!(account: account, name: 'Geral') }

  before do
    create(:team_member, team: team, user: team_agent)
    create(:inbox_member, inbox: inbox, user: outsider)
    Current.user = nil
    Current.account = nil
  end

  # O evento é montado ANTES de mockar o job: criar conversa/contato dispara os
  # broadcasts de `contact_created` & cia, que cairiam no mock e mascarariam a
  # asserção.
  def move_event(funnel)
    stage = FunnelStage.create!(funnel: funnel, name: 'Aberto', position: 0)
    item = FunnelItem.create!(funnel: funnel, funnel_stage: stage, conversation: conversation, moved_at: Time.current)
    Events::Base.new(:'funnel_item.moved', Time.zone.now, funnel_item: item, moved_by: nil)
  end

  describe '#funnel_item_moved' do
    it 'entrega a admins e membros do time do funil' do
      event = move_event(team_funnel)

      expect(ActionCableBroadcastJob).to receive(:perform_later) do |tokens, name, _payload|
        expect(tokens).to contain_exactly(admin.pubsub_token, team_agent.pubsub_token)
        expect(name).to eq('funnel_item.moved')
      end

      listener.funnel_item_moved(event)
    end

    it 'não entrega a quem não consegue abrir o funil' do
      event = move_event(team_funnel)

      expect(ActionCableBroadcastJob).to receive(:perform_later) do |tokens, _name, _payload|
        expect(tokens).not_to include(outsider.pubsub_token)
      end

      listener.funnel_item_moved(event)
    end

    # Funil "Geral" (team_id nil) é só de admin — mesma regra do FunnelPolicy#show?.
    it 'entrega só a admins no funil Geral' do
      event = move_event(general_funnel)

      expect(ActionCableBroadcastJob).to receive(:perform_later) do |tokens, _name, _payload|
        expect(tokens).to contain_exactly(admin.pubsub_token)
      end

      listener.funnel_item_moved(event)
    end

    it 'manda o card completo o bastante para o receptor desenhar' do
      event = move_event(team_funnel)

      expect(ActionCableBroadcastJob).to receive(:perform_later) do |_tokens, _name, payload|
        expect(payload).to include(:id, :funnel_id, :funnel_stage_id, :position, :is_task, :conversation)
        expect(payload[:conversation]).to include(:status, :priority, :contact, :labels)
        expect(payload[:account_id]).to eq(account.id)
      end

      listener.funnel_item_moved(event)
    end

    it 'ignora evento sem funil resolvível' do
      expect(ActionCableBroadcastJob).not_to receive(:perform_later)
      listener.funnel_item_moved(Events::Base.new(:'funnel_item.moved', Time.zone.now, funnel_item: nil))
    end
  end

  describe '#funnel_item_created' do
    it 'entrega o cartão de tarefa ao público do funil' do
      stage = FunnelStage.create!(funnel: team_funnel, name: 'Aberto', position: 0)
      card = FunnelItem.create!(funnel: team_funnel, funnel_stage: stage, title: 'Ligar para o cliente')
      event = Events::Base.new(:'funnel_item.created', Time.zone.now, funnel_item: card)

      expect(ActionCableBroadcastJob).to receive(:perform_later) do |tokens, name, payload|
        expect(tokens).to contain_exactly(admin.pubsub_token, team_agent.pubsub_token)
        expect(name).to eq('funnel_item.created')
        expect(payload).to include(is_task: true, title: 'Ligar para o cliente')
      end

      listener.funnel_item_created(event)
    end
  end

  describe '#funnel_item_deleted' do
    it 'entrega só os ids ao público do funil' do
      item = { id: 42, funnel_id: team_funnel.id, funnel_stage_id: 7 }
      event = Events::Base.new(:'funnel_item.deleted', Time.zone.now, funnel: team_funnel, item: item)

      expect(ActionCableBroadcastJob).to receive(:perform_later) do |tokens, name, payload|
        expect(tokens).to contain_exactly(admin.pubsub_token, team_agent.pubsub_token)
        expect(name).to eq('funnel_item.deleted')
        expect(payload).to include(id: 42, funnel_id: team_funnel.id, funnel_stage_id: 7)
      end

      listener.funnel_item_deleted(event)
    end
  end

  describe '#funnel_items_bulk_moved' do
    let(:stage) { FunnelStage.create!(funnel: team_funnel, name: 'Aberto', position: 0) }

    def bulk_event(item_ids)
      Events::Base.new(:'funnel_items.bulk_moved', Time.zone.now, funnel: team_funnel, item_ids: item_ids)
    end

    it 'manda os cards inteiros abaixo do teto' do
      items = Array.new(3) { |i| FunnelItem.create!(funnel: team_funnel, funnel_stage: stage, title: "Tarefa #{i}") }
      event = bulk_event(items.map(&:id))

      expect(ActionCableBroadcastJob).to receive(:perform_later) do |_tokens, name, payload|
        expect(name).to eq('funnel_items.bulk_moved')
        expect(payload[:items].map { |item| item[:id] }).to match_array(items.map(&:id))
        expect(payload).not_to have_key(:refetch)
      end

      listener.funnel_items_bulk_moved(event)
    end

    # Acima do teto o payload vira ordem de refetch — evita empurrar um JSON
    # gigante pelo websocket para cada pessoa com o board aberto.
    it 'vira ordem de refetch acima do teto' do
      stub_const('ActionCableListener::BULK_ITEMS_PAYLOAD_LIMIT', 2)
      items = Array.new(3) { |i| FunnelItem.create!(funnel: team_funnel, funnel_stage: stage, title: "Tarefa #{i}") }
      event = bulk_event(items.map(&:id))

      expect(ActionCableBroadcastJob).to receive(:perform_later) do |_tokens, _name, payload|
        expect(payload).to include(funnel_id: team_funnel.id, refetch: true)
        expect(payload[:stage_ids]).to eq([stage.id])
        expect(payload).not_to have_key(:items)
      end

      listener.funnel_items_bulk_moved(event)
    end

    it 'não publica nada com a lista vazia' do
      expect(ActionCableBroadcastJob).not_to receive(:perform_later)
      listener.funnel_items_bulk_moved(bulk_event([]))
    end
  end

  describe '#funnel_stages_changed' do
    it 'manda a lista completa e ordenada ao público do funil' do
      later = FunnelStage.create!(funnel: team_funnel, name: 'Fechado', position: 2)
      first = FunnelStage.create!(funnel: team_funnel, name: 'Aberto', position: 1)
      event = Events::Base.new(:'funnel_stages.changed', Time.zone.now, funnel: team_funnel)

      expect(ActionCableBroadcastJob).to receive(:perform_later) do |tokens, name, payload|
        expect(tokens).to contain_exactly(admin.pubsub_token, team_agent.pubsub_token)
        expect(name).to eq('funnel_stages.changed')
        expect(payload[:stages].map { |stage| stage[:id] }).to eq([first.id, later.id])
        expect(payload[:stages].first).to include(:name, :position, :color, :automation_type, :settings)
      end

      listener.funnel_stages_changed(event)
    end

    it 'reflete a coluna apagada (lista relida do banco)' do
      stage = FunnelStage.create!(funnel: team_funnel, name: 'Aberto', position: 1)
      stage.destroy!
      event = Events::Base.new(:'funnel_stages.changed', Time.zone.now, funnel: team_funnel)

      expect(ActionCableBroadcastJob).to receive(:perform_later) do |_tokens, _name, payload|
        expect(payload[:stages]).to be_empty
      end

      listener.funnel_stages_changed(event)
    end
  end

  describe '#funnel_items_reordered' do
    it 'entrega só as posições ao público do funil' do
      positions = [{ id: 1, position: 1 }, { id: 2, position: 2 }]
      event = Events::Base.new(:'funnel_items.reordered', Time.zone.now,
                               funnel: team_funnel, funnel_stage_id: 9, positions: positions)

      expect(ActionCableBroadcastJob).to receive(:perform_later) do |tokens, name, payload|
        expect(tokens).to contain_exactly(admin.pubsub_token, team_agent.pubsub_token)
        expect(name).to eq('funnel_items.reordered')
        expect(payload).to include(funnel_id: team_funnel.id, funnel_stage_id: 9, positions: positions)
      end

      listener.funnel_items_reordered(event)
    end
  end
end
