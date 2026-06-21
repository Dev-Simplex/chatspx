require 'rails_helper'

RSpec.describe Captain::AssistantMirrorService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account, name: 'Sales Assistant') }

  describe '#sync!' do
    it 'creates a captain mirror bot with the assistant attributes and no outgoing_url' do
      mirror = described_class.new(assistant).sync!

      expect(mirror).to be_persisted
      expect(mirror).to be_captain
      expect(mirror.account_id).to eq(account.id)
      expect(mirror.name).to eq('Sales Assistant')
      expect(mirror.description).to eq(assistant.description)
      expect(mirror.outgoing_url).to be_nil
      expect(mirror.captain_assistant_id).to eq(assistant.id)
    end

    it 'is idempotent: syncing twice keeps a single mirror' do
      described_class.new(assistant).sync!
      described_class.new(assistant).sync!

      expect(AgentBot.where(captain_assistant_id: assistant.id).count).to eq(1)
    end

    it 'updates the mirror name when the assistant is renamed' do
      mirror = described_class.new(assistant).sync!

      assistant.name = 'Renamed Assistant'
      described_class.new(assistant).sync!

      expect(mirror.reload.name).to eq('Renamed Assistant')
    end

    context 'with avatar' do
      let(:avatar_file) { fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png') }

      it 'attaches the same blob of the assistant avatar to the mirror' do
        assistant.avatar.attach(avatar_file)
        mirror = described_class.new(assistant).sync!

        expect(mirror.avatar).to be_attached
        expect(mirror.avatar.blob_id).to eq(assistant.avatar.blob_id)
      end

      it 'purges the mirror avatar when the assistant avatar is removed' do
        assistant.avatar.attach(avatar_file)
        mirror = described_class.new(assistant).sync!

        assistant.avatar.purge
        described_class.new(assistant).sync!

        expect(mirror.reload.avatar).not_to be_attached
      end
    end
  end
end
