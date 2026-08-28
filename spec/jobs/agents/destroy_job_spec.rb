require 'rails_helper'

RSpec.describe Agents::DestroyJob do
  subject(:job) { described_class.perform_later(account.id, user.id) }

  let!(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:team1) { create(:team, account: account) }
  let!(:inbox) { create(:inbox, account: account) }

  before do
    create(:team_member, team: team1, user: user)
    create(:inbox_member, inbox: inbox, user: user)
    create(:conversation, account: account, assignee: user, inbox: inbox)
  end

  it 'enqueues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .with(account.id, user.id)
      .on_queue('low')
  end

  describe '#perform' do
    it 'remove inboxes, teams, and conversations when removed from account' do
      described_class.perform_now(account.id, user.id)

      user.reload
      expect(user.teams.length).to eq 0
      expect(user.inboxes.length).to eq 0
      expect(user.notification_settings.length).to eq 0
      expect(user.assigned_conversations.where(account: account).length).to eq 0
    end

    # Sair da conta tirava do grupo de time (efeito colateral do TeamMember), mas
    # DMs e grupos ad-hoc mantinham o ex-agente como membro para sempre — e o
    # broadcast seguia publicando o conteúdo das mensagens no pubsub_token dele.
    it 'removes the user from internal chat channels of that account' do
      dm = create(:internal_channel, :with_two_members, account: account, user_a: user)
      other_account = create(:account)
      foreign_dm = create(:internal_channel, :with_two_members, account: other_account, user_a: user)

      described_class.perform_now(account.id, user.id)

      expect(dm.reload.users).not_to include(user)
      # Só a conta de onde ele saiu: o chat interno de outra conta fica intacto.
      expect(foreign_dm.reload.users).to include(user)
    end
  end
end
