# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Conversations::UpdateMessagesTeamIdJob do
  let(:account) { create(:account) }
  let(:current_team) { create(:team, account: account) }
  let(:old_team) { create(:team, account: account) }
  let(:conversation) { create(:conversation, account: account, team: current_team) }

  def create_message(team_id)
    create(:message, account: account, conversation: conversation).tap do |message|
      message.update!(team_id: team_id)
    end
  end

  it 'atualiza mensagens do time antigo e sem time, preservando as que ja estao corretas' do
    old_message = create_message(old_team.id)
    unassigned_message = create_message(nil)
    current_message = create_message(current_team.id)
    original_ctid = Message.where(id: current_message.id).pick(Arel.sql('ctid::text'))

    described_class.perform_now(conversation.id, old_team.id)

    expect([old_message, unassigned_message, current_message].map { |message| message.reload.team_id }).to eq([current_team.id] * 3)
    expect(Message.where(id: current_message.id).pick(Arel.sql('ctid::text'))).to eq(original_ctid)
  end

  it 'remove o time das mensagens quando a conversa esta sem time' do
    conversation.update!(team: nil)
    message = create_message(old_team.id)

    described_class.perform_now(conversation.id)

    expect(message.reload.team_id).to be_nil
  end

  it 'atualiza todos os lotes quando ha mais mensagens que o tamanho do lote' do
    stub_const('Conversations::UpdateMessagesTeamIdJob::BATCH_SIZE', 2)
    messages = Array.new(5) { create_message(old_team.id) }

    described_class.perform_now(conversation.id)

    expect(messages.map { |message| message.reload.team_id }).to all(eq(current_team.id))
  end

  it 'ignora conversa inexistente' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
