# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InboxIsolationExemption do
  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:agent) { create(:user, account: account, role: :agent) }

  describe 'associations' do
    it { is_expected.to belong_to(:inbox) }
    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    it 'is valid for an agent of the inbox account' do
      expect(described_class.new(inbox: inbox, user: agent, isolation_type: 'agent_message')).to be_valid
    end

    it 'rejects an unknown isolation type' do
      record = described_class.new(inbox: inbox, user: agent, isolation_type: 'conversation')

      expect(record).not_to be_valid
      expect(record.errors[:isolation_type]).to be_present
    end

    it 'rejects a duplicate exemption for the same inbox and isolation type' do
      described_class.create!(inbox: inbox, user: agent, isolation_type: 'agent_message')

      duplicate = described_class.new(inbox: inbox, user: agent, isolation_type: 'agent_message')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:user_id]).to be_present
    end

    # os dois isolamentos são independentes: dá para isentar alguém só do de time
    it 'allows the same user to be exempt from the other isolation in the same inbox' do
      described_class.create!(inbox: inbox, user: agent, isolation_type: 'agent_message')

      expect(described_class.new(inbox: inbox, user: agent, isolation_type: 'team_message')).to be_valid
    end

    it 'allows the same user and type in another inbox' do
      other_inbox = create(:inbox, account: account)
      described_class.create!(inbox: inbox, user: agent, isolation_type: 'agent_message')

      expect(described_class.new(inbox: other_inbox, user: agent, isolation_type: 'agent_message')).to be_valid
    end

    it 'rejects a user that does not belong to the inbox account' do
      outsider = create(:user, account: create(:account), role: :agent)

      record = described_class.new(inbox: inbox, user: outsider, isolation_type: 'agent_message')

      expect(record).not_to be_valid
      expect(record.errors[:user]).to be_present
    end
  end

  describe 'uniqueness at the database level' do
    it 'has a unique index on the inbox, user and isolation type triple' do
      index = ActiveRecord::Base.connection.indexes(:inbox_isolation_exemptions)
                                .find { |i| i.columns == %w[inbox_id user_id isolation_type] }

      expect(index).to be_present
      expect(index.unique).to be(true)
    end
  end

  describe 'dependent destroy' do
    before { described_class.create!(inbox: inbox, user: agent, isolation_type: 'agent_message') }

    it 'goes away with the user' do
      expect { agent.destroy! }.to change(described_class, :count).by(-1)
    end

    it 'goes away with the inbox' do
      expect { inbox.destroy! }.to change(described_class, :count).by(-1)
    end

    # criterio 7: tirar o agente da caixa (inclusive quando ele sai da conta, que
    # destroi os inbox_members) nao pode deixar isencao apontando para nao-membro,
    # senao uma readmissao devolveria a isencao em silencio
    it 'goes away when the agent stops being a member of the inbox' do
      member = create(:inbox_member, inbox: inbox, user: agent)

      expect { member.destroy! }.to change(described_class, :count).by(-1)
    end
  end

  describe 'database constraints' do
    it 'cascades the delete of the inbox and of the user' do
      foreign_keys = ActiveRecord::Base.connection.foreign_keys(:inbox_isolation_exemptions)

      expect(foreign_keys.map { |fk| [fk.to_table, fk.on_delete] }).to contain_exactly(%w[inboxes].push(:cascade), %w[users].push(:cascade))
    end
  end

  describe 'participants derived on the inbox' do
    let!(:admin) { create(:user, account: account, role: :administrator) }
    let!(:other_agent) { create(:user, account: account, role: :agent) }

    before do
      create(:inbox_member, inbox: inbox, user: agent)
      create(:inbox_member, inbox: inbox, user: other_agent)
      create(:inbox_member, inbox: inbox, user: admin)
    end

    # lista vazia de excecoes = comportamento de hoje: todo mundo participa
    it 'returns every non admin member when there is no exemption' do
      expect(inbox.reload.isolation_participant_ids('agent_message')).to contain_exactly(agent.id, other_agent.id)
    end

    it 'never lists the administrator as a participant' do
      expect(inbox.reload.isolation_participant_ids('team_message')).not_to include(admin.id)
    end

    it 'drops the exempt agent from the participants of that isolation only' do
      described_class.create!(inbox: inbox, user: agent, isolation_type: 'agent_message')
      inbox.reload

      expect(inbox.isolation_participant_ids('agent_message')).to contain_exactly(other_agent.id)
      expect(inbox.isolation_participant_ids('team_message')).to contain_exactly(agent.id, other_agent.id)
    end
  end
end
