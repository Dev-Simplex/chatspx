# frozen_string_literal: true

require 'rails_helper'

# Kanban v2 (Fase 4) — moving a card dispatches the real-time FUNNEL_ITEM_MOVED
# event, but a no-op "move" to the same stage stays quiet.
RSpec.describe FunnelItems::MoveService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:funnel) { Funnel.create!(account: account, name: 'Vendas') }
  let(:stage_a) { FunnelStage.create!(funnel: funnel, name: 'Aberto', position: 0) }
  let(:stage_b) { FunnelStage.create!(funnel: funnel, name: 'Em atendimento', position: 1) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  before { allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original }

  def move_to(stage)
    described_class.new(conversation: conversation, funnel: funnel, funnel_stage: stage, moved_by: nil).perform
  end

  it 'dispatches FUNNEL_ITEM_MOVED on first placement' do
    move_to(stage_a)
    expect(Rails.configuration.dispatcher).to have_received(:dispatch)
      .with(Events::Types::FUNNEL_ITEM_MOVED, anything, hash_including(:funnel_item))
  end

  it 'dispatches FUNNEL_ITEM_MOVED when the stage actually changes' do
    move_to(stage_a)
    move_to(stage_b)
    expect(Rails.configuration.dispatcher).to have_received(:dispatch)
      .with(Events::Types::FUNNEL_ITEM_MOVED, anything, hash_including(:funnel_item)).twice
  end

  it 'does not dispatch on a no-op move to the same stage' do
    move_to(stage_a)
    move_to(stage_a)
    expect(Rails.configuration.dispatcher).to have_received(:dispatch)
      .with(Events::Types::FUNNEL_ITEM_MOVED, anything, hash_including(:funnel_item)).once
  end

  it 'never lets a broadcast failure break the move' do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
      .with(Events::Types::FUNNEL_ITEM_MOVED, anything, anything).and_raise(StandardError, 'boom')

    expect { move_to(stage_a) }.not_to raise_error
    expect(FunnelItem.find_by(conversation: conversation, funnel: funnel).funnel_stage_id).to eq(stage_a.id)
  end
end
