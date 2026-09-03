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
        # Evento de digitacao leva payload ENXUTO — `{ id: display_id }` — e nao o
        # `push_event_data` inteiro (ver action_cable_listener.rb:107). Os outros tres exemplos
        # deste arquivo (linhas 68, 88 e o typing_off) ja usam a forma certa; so este destoava.
        # O payload de digitacao classifica o autor em apenas DUAS categorias
        # (`user.is_a?(Contact) ? 'contact' : 'user'`), entao um agent bot e reportado como
        # 'user' e vai com o hash minimo — nao com o `push_event_data`. Os outros tres exemplos
        # deste arquivo ja usam essa forma.
        #
        # OBSERVACAO registrada, nao consertada aqui: o painel nao consegue distinguir "a IA
        # esta digitando" de "um agente esta digitando". Mudar isso altera o payload consumido
        # em tempo real pelo dashboard — e decisao de produto, nao de triagem.
        'conversation.typing_on', { conversation: { id: conversation.display_id },
                                    user: { id: agent_bot.id, name: agent_bot.name, type: 'user' },
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

  # PR B1 — emoji reactions are broadcast to the same audience as message.updated
  # (inbox members, account admins and the contact for non-private messages).
  describe '#message_reaction_added' do
    let(:event_name) { :'message.reaction_added' }
    let!(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'outgoing') }
    let!(:reaction) { create(:message_reaction, message: message, account: account, reactor: agent, emoji: '👍') }
    let!(:event) { Events::Base.new(event_name, Time.zone.now, message: message, reaction: reaction) }

    it 'broadcasts MESSAGE_REACTION_ADDED to inbox members, admins and the contact' do
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)

      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          agent.pubsub_token, admin.pubsub_token, conversation.contact_inbox.pubsub_token
        ),
        'message.reaction_added',
        hash_including(
          message_id: message.id,
          conversation_id: conversation.display_id,
          reaction: reaction.push_event_data,
          account_id: account.id
        )
      )
      listener.message_reaction_added(event)
    end
  end

  describe '#message_reaction_removed' do
    let(:event_name) { :'message.reaction_removed' }
    let!(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'outgoing') }
    let!(:reaction) { create(:message_reaction, message: message, account: account, reactor: agent, emoji: '👍') }
    # O evento de remocao carrega VALORES, nao o registro — no `destroy` a linha ja foi apagada
    # e o job estouraria ao reidratar por GlobalID; na troca de emoji o registro sobrevive com o
    # emoji NOVO, que e o oposto do que o assinante precisa.
    let!(:event) do
      Events::Base.new(event_name, Time.zone.now, message: message, reaction_id: reaction.id,
                                                  emoji: reaction.emoji, user_id: reaction.user_id,
                                                  user_type: reaction.user_type)
    end

    it 'broadcasts MESSAGE_REACTION_REMOVED with reaction_id and emoji' do
      expect(conversation.inbox.reload.inbox_members.count).to eq(1)

      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        a_collection_containing_exactly(
          agent.pubsub_token, admin.pubsub_token, conversation.contact_inbox.pubsub_token
        ),
        'message.reaction_removed',
        hash_including(
          message_id: message.id,
          conversation_id: conversation.display_id,
          reaction_id: reaction.id,
          emoji: '👍',
          user_id: agent.id,
          user_type: 'User',
          account_id: account.id
        )
      )
      listener.message_reaction_removed(event)
    end
  end

  # PR G1 — pin é coletivo: broadcast para todos os agents/admins do inbox.
  describe '#conversation_pin_added' do
    let(:event_name) { :'conversation.pin_added' }
    let(:message) { create(:message, conversation: conversation, account: account, inbox: inbox) }
    let!(:event) do
      Events::Base.new(
        event_name,
        Time.zone.now,
        conversation: conversation,
        message_id: message.id,
        pinned_message_ids: [message.id]
      )
    end

    it 'broadcasts to all inbox members and admins' do
      expect(ActionCableBroadcastJob).to receive(:perform_later) do |tokens, name, payload|
        expect(tokens).to include(agent.pubsub_token, admin.pubsub_token)
        expect(name).to eq('conversation.pin_added')
        expect(payload[:conversation][:id]).to eq(conversation.display_id)
        expect(payload[:message_id]).to eq(message.id)
        expect(payload[:pinned_message_ids]).to eq([message.id])
        expect(payload[:account_id]).to eq(account.id)
      end

      listener.conversation_pin_added(event)
    end

    it 'does nothing when conversation is missing' do
      blank_event = Events::Base.new(event_name, Time.zone.now, conversation: nil, message_id: message.id)
      expect(ActionCableBroadcastJob).not_to receive(:perform_later)
      listener.conversation_pin_added(blank_event)
    end
  end

  describe '#conversation_pin_removed' do
    let(:event_name) { :'conversation.pin_removed' }
    let(:message) { create(:message, conversation: conversation, account: account, inbox: inbox) }
    let!(:event) do
      Events::Base.new(
        event_name,
        Time.zone.now,
        conversation: conversation,
        message_id: message.id,
        pinned_message_ids: []
      )
    end

    it 'broadcasts to all inbox members and admins' do
      expect(ActionCableBroadcastJob).to receive(:perform_later) do |tokens, name, payload|
        expect(tokens).to include(agent.pubsub_token, admin.pubsub_token)
        expect(name).to eq('conversation.pin_removed')
        expect(payload[:pinned_message_ids]).to eq([])
        expect(payload[:message_id]).to eq(message.id)
      end

      listener.conversation_pin_removed(event)
    end
  end
end
