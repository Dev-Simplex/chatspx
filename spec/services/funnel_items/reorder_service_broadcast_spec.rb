# frozen_string_literal: true

require 'rails_helper'

# Kanban tempo real (Fase 3) — reordenar dentro da coluna também é arraste.
# Espelha spec/services/funnel_items/move_service_broadcast_spec.rb.
RSpec.describe FunnelItems::ReorderService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:funnel) { Funnel.create!(account: account, name: 'Vendas') }
  let(:stage) { FunnelStage.create!(funnel: funnel, name: 'Aberto', position: 0) }
  let(:other_stage) { FunnelStage.create!(funnel: funnel, name: 'Fechado', position: 1) }

  let(:items) do
    Array.new(3) do |i|
      FunnelItem.create!(funnel: funnel, funnel_stage: stage, conversation: create(:conversation, account: account, inbox: inbox), position: i + 1)
    end
  end

  before { allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original }

  def reorder(ids, stage_id: stage.id)
    described_class.new(funnel: funnel, funnel_stage_id: stage_id, item_ids: ids).perform
  end

  it 'dispara FUNNEL_ITEMS_REORDERED com as posições 1-based na nova ordem' do
    reversed = items.reverse.map(&:id)
    reorder(reversed)

    expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(
      Events::Types::FUNNEL_ITEMS_REORDERED,
      anything,
      hash_including(
        funnel: funnel,
        funnel_stage_id: stage.id,
        positions: reversed.each_with_index.map { |id, index| { id: id, position: index + 1 } }
      )
    )
  end

  it 'não dispara quando não há nada válido para reordenar' do
    reorder([items.first.id], stage_id: other_stage.id)

    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
      .with(Events::Types::FUNNEL_ITEMS_REORDERED, anything, anything)
  end

  it 'nunca deixa uma falha de broadcast quebrar a reordenação' do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
      .with(Events::Types::FUNNEL_ITEMS_REORDERED, anything, anything).and_raise(StandardError, 'boom')

    reversed = items.reverse.map(&:id)
    expect { reorder(reversed) }.not_to raise_error
    expect(FunnelItem.find(reversed.first).position).to eq(1)
  end
end
