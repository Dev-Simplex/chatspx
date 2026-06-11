# frozen_string_literal: true

require 'rails_helper'

# A5: CaptainInbox vira ELEGIBILIDADE (uniqueness composta no PAR, espelhando o índice DB).
RSpec.describe CaptainInbox do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:other_assistant) { create(:captain_assistant, account: account) }

  describe 'uniqueness composta scope: :captain_assistant_id' do
    it 'permite 2 assistants distintos elegíveis na MESMA inbox' do
      create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
      second = build(:captain_inbox, captain_assistant: other_assistant, inbox: inbox)

      expect(second).to be_valid
      expect { second.save! }.not_to raise_error
    end

    it 'rejeita o MESMO par (assistant + inbox) duas vezes via validação' do
      create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
      duplicate = build(:captain_inbox, captain_assistant: assistant, inbox: inbox)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:inbox_id]).to be_present
    end

    it 'o índice único do par barra o mesmo par no nível raw (RecordNotUnique)' do
      create(:captain_inbox, captain_assistant: assistant, inbox: inbox)

      expect do
        described_class.new(captain_assistant: assistant, inbox: inbox).save!(validate: false)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'permite o MESMO assistant elegível em inboxes diferentes' do
      other_inbox = create(:inbox, account: account)
      create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
      second = build(:captain_inbox, captain_assistant: assistant, inbox: other_inbox)

      expect(second).to be_valid
    end
  end
end
