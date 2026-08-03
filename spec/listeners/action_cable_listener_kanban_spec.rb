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
end
