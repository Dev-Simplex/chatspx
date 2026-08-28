# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountUser do
  include ActiveJob::TestHelper

  let!(:account_user) { create(:account_user) }
  let!(:inbox) { create(:inbox, account: account_user.account) }

  describe 'notification_settings' do
    it 'gets created with the right default settings' do
      expect(account_user.user.notification_settings).not_to be_nil

      expect(account_user.user.notification_settings.first.email_conversation_creation?).to be(false)
      expect(account_user.user.notification_settings.first.email_conversation_assignment?).to be(true)
    end
  end

  describe 'permissions' do
    it 'returns the right permissions' do
      expect(account_user.permissions).to eq(['agent'])
    end

    it 'returns the right permissions for administrator' do
      account_user.administrator!
      expect(account_user.permissions).to eq(['administrator'])
    end
  end

  # Virar administrador tira a pessoa da lista de participantes do isolamento (só agentes
  # entram lá): a exceção dela sumiria da tela e ninguém mais conseguiria removê-la. Quem
  # impede o vazamento é a guarda de leitura (User#fetch_isolation_exempt_inbox_ids); isto
  # aqui apaga a linha para ela não voltar a valer calada numa despromoção.
  describe 'isolation exemptions on role change' do
    let!(:other_account) { create(:account) }
    let!(:other_inbox) { create(:inbox, account: other_account) }

    before { create(:account_user, account: other_account, user: account_user.user, role: :agent) }

    it 'drops the exemptions of this account when the agent becomes an administrator' do
      create(:inbox_isolation_exemption, inbox: inbox, user: account_user.user, isolation_type: 'agent_message')
      create(:inbox_isolation_exemption, inbox: inbox, user: account_user.user, isolation_type: 'team_message')

      account_user.administrator!

      expect(InboxIsolationExemption.where(user_id: account_user.user_id)).to be_empty
    end

    # A mesma pessoa pode ser agente isentado em OUTRA conta: virar administrador aqui não
    # pode mexer no que ela enxerga lá.
    it 'does not touch the exemptions of another account' do
      create(:inbox_isolation_exemption, inbox: other_inbox, user: account_user.user, isolation_type: 'agent_message')

      account_user.administrator!

      expect(InboxIsolationExemption.where(user_id: account_user.user_id).pluck(:inbox_id)).to contain_exactly(other_inbox.id)
    end

    it 'keeps the exemptions when the role does not change' do
      create(:inbox_isolation_exemption, inbox: inbox, user: account_user.user, isolation_type: 'agent_message')

      account_user.update!(availability: :busy)

      expect(InboxIsolationExemption.where(user_id: account_user.user_id).count).to eq(1)
    end
  end

  describe 'destroy call agent::destroy service' do
    it 'gets created with the right default settings' do
      create(:conversation, account: account_user.account, assignee: account_user.user, inbox: inbox)
      user = account_user.user

      expect(user.assigned_conversations.count).to eq(1)

      perform_enqueued_jobs do
        account_user.destroy!
      end

      expect(user.assigned_conversations.count).to eq(0)
    end
  end
end
