require 'rails_helper'
describe ActionCableListener do
  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: agent) }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    Current.user = nil
    Current.account = nil
  end

  describe '#message_created' do
    let(:event_name) { :'message.created' }
    let!(:message) do
      create(:message, message_type: 'outgoing',
                       account: account, inbox: inbox, conversation: conversation)
    end
    let!(:event) { Events::Base.new(event_name, Time.zone.now, message: message) }

    it 'sends message to account admins, inbox agents and the contact' do
      # HACK: to reload conversation inbox members
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)

      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          agent.pubsub_token, admin.pubsub_token, conversation.contact_inbox.pubsub_token
        ),
        'message.created',
        message.push_event_data.merge(account_id: account.id)
      )
      listener.message_created(event)
    end

    it 'sends message to all hmac verified contact inboxes' do
      # HACK: to reload conversation inbox members
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)
      conversation.contact_inbox.update(hmac_verified: true)
      # creating a non verified contact inbox to ensure the events are not sent to it
      create(:contact_inbox, contact: conversation.contact, inbox: inbox)
      verified_contact_inbox = create(:contact_inbox, contact: conversation.contact, inbox: inbox, hmac_verified: true)

      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          agent.pubsub_token, admin.pubsub_token, conversation.contact_inbox.pubsub_token, verified_contact_inbox.pubsub_token
        ),
        'message.created',
        message.push_event_data.merge(account_id: account.id)
      )
      listener.message_created(event)
    end
  end

  describe '#typing_on' do
    let(:event_name) { :'conversation.typing_on' }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation, user: agent, is_private: false) }

    it 'sends message to account admins, inbox agents and the contact' do
      # HACK: to reload conversation inbox members
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          admin.pubsub_token, conversation.contact_inbox.pubsub_token
        ),
        'conversation.typing_on', { conversation: { id: conversation.display_id },
                                    user: { id: agent.id, name: agent.name, type: 'user' },
                                    account_id: account.id,
                                    is_private: false }
      )
      listener.conversation_typing_on(event)
    end
  end

  describe '#typing_on with contact' do
    let(:event_name) { :'conversation.typing_on' }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation, user: conversation.contact, is_private: false) }

    it 'sends message to account admins, inbox agents and the contact' do
      # HACK: to reload conversation inbox members
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          admin.pubsub_token, agent.pubsub_token
        ),
        'conversation.typing_on', { conversation: { id: conversation.display_id },
                                    user: { id: conversation.contact.id, name: conversation.contact.name, type: 'contact' },
                                    account_id: account.id,
                                    is_private: false }
      )
      listener.conversation_typing_on(event)
    end
  end

  describe '#typing_on with agent bot' do
    let(:event_name) { :'conversation.typing_on' }
    let!(:agent_bot) { create(:agent_bot, account: account) }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation, user: agent_bot, is_private: false) }

    it 'sends message to account admins, inbox agents and the contact' do
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          admin.pubsub_token, agent.pubsub_token, conversation.contact_inbox.pubsub_token
        ),
        'conversation.typing_on', { conversation: conversation.push_event_data,
                                    user: agent_bot.push_event_data,
                                    account_id: account.id,
                                    is_private: false }
      )
      listener.conversation_typing_on(event)
    end
  end

  describe '#typing_off' do
    let(:event_name) { :'conversation.typing_off' }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation, user: agent, is_private: false) }

    it 'sends message to account admins, inbox agents and the contact' do
      # HACK: to reload conversation inbox members
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          admin.pubsub_token, conversation.contact_inbox.pubsub_token
        ),
        'conversation.typing_off', { conversation: { id: conversation.display_id },
                                     user: { id: agent.id, name: agent.name, type: 'user' },
                                     account_id: account.id,
                                     is_private: false }
      )
      listener.conversation_typing_off(event)
    end
  end

  describe '#contact_deleted' do
    let(:event_name) { :'contact.deleted' }
    let!(:contact) { create(:contact, account: account) }
    let(:contact_data) { contact.push_event_data.merge(account_id: contact.account_id) }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, contact_data: contact_data) }

    it 'sends message to account admins, inbox agents' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        ["account_#{account.id}"],
        'contact.deleted',
        contact_data
      )
      listener.contact_deleted(event)
    end
  end

  describe '#notification_deleted' do
    let(:event_name) { :'notification.deleted' }
    let!(:notification) { create(:notification, account: account, user: agent) }
    let(:notification_data) do
      {
        id: notification.id,
        user_id: agent.id,
        account_id: account.id
      }
    end
    let!(:event) { Events::Base.new(event_name, Time.zone.now, notification_data: notification_data) }

    it 'sends message to account admins, inbox agents' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        [agent.pubsub_token],
        'notification.deleted',
        {
          account_id: notification.account_id,
          notification: {
            id: notification.id
          },
          unread_count: 1,
          count: 1
        }
      )

      listener.notification_deleted(event)
    end
  end

  describe '#notification_updated' do
    let(:event_name) { :'notification.updated' }
    let!(:notification) { create(:notification, account: account, user: agent) }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, notification: notification) }

    it 'sends notification to account admins, inbox agents' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        [agent.pubsub_token],
        'notification.updated',
        {
          account_id: notification.account_id,
          notification: notification.push_event_data,
          unread_count: 1,
          count: 1
        }
      )

      listener.notification_updated(event)
    end
  end

  describe '#conversation_updated' do
    let(:event_name) { :'conversation.updated' }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation, user: agent, is_private: false) }

    before do
      conversation.add_labels(['support'])
    end

    it 'sends update to inbox members' do
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)

      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        [agent.pubsub_token, admin.pubsub_token, conversation.contact_inbox.pubsub_token],
        'conversation.updated',
        conversation.push_event_data.merge(account_id: account.id)
      )
      listener.conversation_updated(event)
    end

    it 'broadcast event with label data' do
      expect(conversation.reload.push_event_data[:labels]).to eq(conversation.labels.pluck(:name))

      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        [agent.pubsub_token, admin.pubsub_token, conversation.contact_inbox.pubsub_token],
        'conversation.updated',
        conversation.push_event_data.merge(account_id: account.id)
      )
      listener.conversation_updated(event)
    end
  end

  # PR B4 — broadcast restricted to the owning user (per-user settings privacy).
  describe '#conversation_user_setting_changed' do
    let(:event_name) { :'conversation.user_setting_changed' }
    let!(:other_agent) { create(:user, account: account, role: :agent) }
    let!(:event) do
      Events::Base.new(event_name, Time.zone.now, conversation: conversation, user_id: agent.id)
    end

    before do
      create(:inbox_member, inbox: inbox, user: other_agent)
      conversation.update!(
        additional_attributes: { 'user_settings' => { agent.id.to_s => { 'pinned' => true } } }
      )
    end

    it 'broadcasts only to the owning user, not to other agents or admins' do
      expect(ActionCableBroadcastJob).to receive(:perform_later) do |tokens, name, payload|
        expect(tokens).to eq([agent.pubsub_token])
        expect(tokens).not_to include(other_agent.pubsub_token, admin.pubsub_token)
        expect(name).to eq('conversation.user_setting_changed')
        expect(payload[:user_id]).to eq(agent.id)
        expect(payload[:user_settings]).to eq('pinned' => true)
        expect(payload[:conversation][:id]).to eq(conversation.display_id)
        expect(payload[:account_id]).to eq(account.id)
      end

      listener.conversation_user_setting_changed(event)
    end

    it 'does nothing when user_id is blank' do
      blank_event = Events::Base.new(event_name, Time.zone.now, conversation: conversation, user_id: nil)
      expect(ActionCableBroadcastJob).not_to receive(:perform_later)
      listener.conversation_user_setting_changed(blank_event)
    end

    it 'does nothing when user no longer exists' do
      missing_event = Events::Base.new(event_name, Time.zone.now, conversation: conversation, user_id: -1)
      expect(ActionCableBroadcastJob).not_to receive(:perform_later)
      listener.conversation_user_setting_changed(missing_event)
    end
  end
end
