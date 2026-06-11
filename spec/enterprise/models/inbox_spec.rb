# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inbox do
  let!(:inbox) { create(:inbox) }

  describe 'member_ids_with_assignment_capacity' do
    let!(:inbox_member_1) { create(:inbox_member, inbox: inbox) }
    let!(:inbox_member_2) { create(:inbox_member, inbox: inbox) }
    let!(:inbox_member_3) { create(:inbox_member, inbox: inbox) }
    let!(:inbox_member_4) { create(:inbox_member, inbox: inbox) }

    before do
      create(:conversation, inbox: inbox, assignee: inbox_member_1.user)
      # to test conversations in other inboxes won't impact
      create_list(:conversation, 3, assignee: inbox_member_1.user)
      create_list(:conversation, 2, inbox: inbox, account: inbox.account, assignee: inbox_member_2.user)
      create_list(:conversation, 3, inbox: inbox, account: inbox.account, assignee: inbox_member_3.user)
    end

    it 'validated max_assignment_limit' do
      account = create(:account)
      expect(build(:inbox, account: account, auto_assignment_config: { max_assignment_limit: 0 })).not_to be_valid
      expect(build(:inbox, account: account, auto_assignment_config: {})).to be_valid
      expect(build(:inbox, account: account, auto_assignment_config: { max_assignment_limit: 1 })).to be_valid
    end

    it 'returns member ids with assignment capacity with inbox max_assignment_limit is configured' do
      # agent 1 has 1 conversations, agent 2 has 2 conversations, agent 3 has 3 conversations and agent 4 with none
      inbox.update(auto_assignment_config: { max_assignment_limit: 2 })
      expect(inbox.member_ids_with_assignment_capacity).to contain_exactly(inbox_member_1.user_id, inbox_member_4.user_id)
    end

    it 'returns all member ids when inbox max_assignment_limit is not configured' do
      expect(inbox.member_ids_with_assignment_capacity).to match_array(inbox.members.ids)
    end
  end

  # A5: flip has_one captain_assistant -> has_many captain_assistants (through captain_inboxes)
  describe 'captain elegibilidade (has_many)' do
    let(:account) { create(:account) }
    let(:eligible_inbox) { create(:inbox, account: account) }
    let(:assistant_one) { create(:captain_assistant, account: account) }
    let(:assistant_two) { create(:captain_assistant, account: account) }

    it 'retorna TODOS os assistants elegíveis da inbox' do
      create(:captain_inbox, captain_assistant: assistant_one, inbox: eligible_inbox)
      create(:captain_inbox, captain_assistant: assistant_two, inbox: eligible_inbox)

      expect(eligible_inbox.captain_assistants).to contain_exactly(assistant_one, assistant_two)
    end

    it 'destruir o assistant remove a elegibilidade (dependent: :destroy no captain_inbox)' do
      create(:captain_inbox, captain_assistant: assistant_one, inbox: eligible_inbox)
      expect { assistant_one.destroy! }.to change { eligible_inbox.reload.captain_assistants.count }.from(1).to(0)
    end

    it 'destruir a inbox remove os captain_inboxes (dependent: :destroy)' do
      create(:captain_inbox, captain_assistant: assistant_one, inbox: eligible_inbox)
      create(:captain_inbox, captain_assistant: assistant_two, inbox: eligible_inbox)

      expect { eligible_inbox.destroy! }.to change(CaptainInbox, :count).by(-2)
    end
  end

  # A9.1: captain_active? re-keyado pra ELEGIBILIDADE + cota; active_bot? composto.
  describe '#captain_active?' do
    let(:account) { create(:account) }
    let(:captain_inbox) { create(:inbox, account: account) }
    let(:assistant_one) { create(:captain_assistant, account: account) }
    let(:assistant_two) { create(:captain_assistant, account: account) }

    def stub_quota(available)
      allow(account).to receive(:usage_limits).and_return(captain: { responses: { current_available: available } })
      allow(captain_inbox).to receive(:account).and_return(account)
    end

    it 'true quando há 2 assistants elegíveis e cota disponível' do
      create(:captain_inbox, captain_assistant: assistant_one, inbox: captain_inbox)
      create(:captain_inbox, captain_assistant: assistant_two, inbox: captain_inbox)
      stub_quota(5)

      expect(captain_inbox.captain_active?).to be(true)
    end

    it 'false quando NÃO há assistant elegível (mesmo com cota)' do
      stub_quota(5)

      expect(captain_inbox.captain_active?).to be(false)
    end

    it 'false quando há elegível mas a cota está zerada' do
      create(:captain_inbox, captain_assistant: assistant_one, inbox: captain_inbox)
      stub_quota(0)

      expect(captain_inbox.captain_active?).to be(false)
    end
  end

  describe '#active_bot? (composto super || captain_active?)' do
    let(:account) { create(:account) }
    let(:captain_inbox) { create(:inbox, account: account) }
    let(:assistant_one) { create(:captain_assistant, account: account) }

    it 'true quando a inbox é elegível para captain e há cota' do
      create(:captain_inbox, captain_assistant: assistant_one, inbox: captain_inbox)
      allow(account).to receive(:usage_limits).and_return(captain: { responses: { current_available: 1 } })
      allow(captain_inbox).to receive(:account).and_return(account)

      expect(captain_inbox.active_bot?).to be(true)
    end

    it 'cai no super (webhook agent bot) quando não há captain elegível' do
      bot_inbox = create(:inbox, account: account)
      create(:agent_bot_inbox, inbox: bot_inbox)

      expect(bot_inbox.active_bot?).to be(true)
    end

    it 'false quando não há captain elegível nem agent bot' do
      plain_inbox = create(:inbox, account: account)

      expect(plain_inbox.active_bot?).to be(false)
    end
  end

  describe 'audit log' do
    context 'when inbox is created' do
      it 'has associated audit log created' do
        expect(Audited::Audit.where(auditable_type: 'Inbox', action: 'create').count).to eq(1)
      end
    end

    context 'when inbox is updated' do
      it 'has associated audit log created' do
        inbox.update(name: 'Updated Inbox')
        expect(Audited::Audit.where(auditable_type: 'Inbox', action: 'update').count).to eq(1)
      end
    end

    context 'when channel is updated' do
      it 'has associated audit log created' do
        previous_color = inbox.channel.widget_color
        new_color = '#ff0000'
        inbox.channel.update(widget_color: new_color)

        # check if channel update creates an audit log against inbox
        expect(Audited::Audit.where(auditable_type: 'Inbox', action: 'update').count).to eq(1)
        # Check for the specific widget_color update in the audit log
        expect(Audited::Audit.where(auditable_type: 'Inbox', action: 'update',
                                    audited_changes: { 'widget_color' => [previous_color, new_color] }).count).to eq(1)
      end
    end
  end

  describe 'audit log with api channel' do
    let!(:channel) { create(:channel_api) }
    let!(:inbox) { channel.inbox }

    context 'when inbox is created' do
      it 'has associated audit log created' do
        expect(Audited::Audit.where(auditable_type: 'Inbox', action: 'create').count).to eq(1)
      end
    end

    context 'when inbox is updated' do
      it 'has associated audit log created' do
        inbox.update(name: 'Updated Inbox')
        expect(Audited::Audit.where(auditable_type: 'Inbox', action: 'update').count).to eq(1)
      end
    end

    context 'when channel is updated' do
      it 'has associated audit log created' do
        previous_webhook = inbox.channel.webhook_url
        new_webhook = 'https://example2.com'
        inbox.channel.update(webhook_url: new_webhook)

        # check if channel update creates an audit log against inbox
        expect(Audited::Audit.where(auditable_type: 'Inbox', action: 'update').count).to eq(1)
        # Check for the specific webhook_update update in the audit log
        expect(Audited::Audit.where(auditable_type: 'Inbox', action: 'update',
                                    audited_changes: { 'webhook_url' => [previous_webhook, new_webhook] }).count).to eq(1)
      end
    end
  end

  describe 'audit log with whatsapp channel' do
    let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:inbox) { channel.inbox }

    before do
      stub_request(:get, 'https://graph.facebook.com/v14.0//message_templates?access_token=test_key')
        .with(
          headers: {
            'Accept' => '*/*',
            'Accept-Encoding' => 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
            'User-Agent' => 'Ruby'
          }
        )
        .to_return(status: 200, body: '', headers: {})
    end

    context 'when inbox is created' do
      it 'has associated audit log created' do
        expect(Audited::Audit.where(auditable_type: 'Inbox', action: 'create').count).to eq(1)
      end
    end

    context 'when inbox is updated' do
      it 'has associated audit log created' do
        inbox.update(name: 'Updated Inbox')
        expect(Audited::Audit.where(auditable_type: 'Inbox', action: 'update').count).to eq(1)
      end
    end

    context 'when channel is updated' do
      it 'has associated audit log created' do
        previous_phone_number = inbox.channel.phone_number
        new_phone_number = '1234567890'
        inbox.channel.update(phone_number: new_phone_number)

        # check if channel update creates an audit log against inbox
        expect(Audited::Audit.where(auditable_type: 'Inbox', action: 'update').count).to eq(1)
        # Check for the specific phone_number update in the audit log
        expect(Audited::Audit.where(auditable_type: 'Inbox', action: 'update',
                                    audited_changes: { 'phone_number' => [previous_phone_number, new_phone_number] }).count).to eq(1)
      end
    end

    context 'when template sync runs' do
      it 'has no associated audit log created' do
        channel.sync_templates
        # check if template sync does not create an audit log
        expect(Audited::Audit.where(auditable_type: 'Inbox', action: 'update').count).to eq(0)
      end
    end
  end
end
