# frozen_string_literal: true

require 'rails_helper'

# Regressão: a subquery de "conversas que já estão no funil" incluía os cartões
# de TAREFA, que têm `conversation_id` NULO. Em SQL, `id NOT IN (1, 2, NULL)`
# nunca é verdadeiro — então bastava UM cartão de tarefa no funil para o backfill
# deixar de achar candidatas e nenhuma conversa nova entrar mais no board.
RSpec.describe Kanban::FunnelItemsBackfillService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:funnel) { Funnel.create!(account: account, name: 'Vendas') }
  let!(:aberto) { FunnelStage.create!(funnel: funnel, name: 'Aberto', position: 0, automation_type: 'open') }

  let!(:conversa_solta) { create(:conversation, account: account, inbox: inbox, status: :open) }

  def backfill
    described_class.new(account: account, funnel: funnel, moved_by_id: nil).perform
  end

  it 'coloca no board a conversa que ainda não tem cartão' do
    expect { backfill }.to change { funnel.funnel_items.where(conversation_id: conversa_solta.id).count }.from(0).to(1)
  end

  it 'continua achando candidatas mesmo com cartão de tarefa no funil' do
    FunnelItem.create!(funnel: funnel, funnel_stage: aberto, title: 'Tarefa avulsa')

    expect { backfill }.to change { funnel.funnel_items.where(conversation_id: conversa_solta.id).count }.from(0).to(1)
  end

  it 'não duplica cartão de conversa que já está no funil' do
    FunnelItem.create!(funnel: funnel, funnel_stage: aberto, conversation: conversa_solta)

    expect { backfill }.not_to(change { funnel.funnel_items.count })
  end
end
