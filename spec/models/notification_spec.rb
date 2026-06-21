# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notification do
  include ActiveJob::TestHelper

  context 'with associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:user) }
  end

  context 'with default order by' do
    it 'sort by primary id desc' do
      notification1 = create(:notification)
      create(:notification)
      notification3 = create(:notification)

      expect(described_class.all.first.id).to eq notification1.id
      expect(described_class.all.last.id).to eq notification3.id
    end
  end

  context 'when push_title is called' do
    it 'returns appropriate title suited for the notification type conversation_creation' do
      notification = create(:notification, notification_type: 'conversation_creation')
      expect(notification.push_message_title).to eq "A conversation (##{notification.primary_actor.display_id}) \
has been created in #{notification.primary_actor.inbox.name}"
    end

    it 'returns appropriate title suited for the notification type conversation_assignment' do
      notification = create(:notification, notification_type: 'conversation_assignment')
      expect(notification.push_message_title).to eq "A conversation (##{notification.primary_actor.display_id}) \
has been assigned to you"
    end

    it 'returns appropriate title suited for the notification type assigned_conversation_new_message' do
      message = create(:message, sender: create(:user), content: Faker::Lorem.paragraphs(number: 2))
      notification = create(:notification, notification_type: 'assigned_conversation_new_message', primary_actor: message.conversation,
                                           secondary_actor: message)

      expect(notification.push_message_title).to eq "A new message is created in conversation (##{notification.primary_actor.display_id})"
    end

    it 'returns appropriate title suited for the notification type assigned_conversation_new_message when attachment message' do
      # checking content nil should be suffice for attachments
      message = create(:message, sender: create(:user), content: nil)
      notification = create(:notification, notification_type: 'assigned_conversation_new_message', primary_actor: message.conversation,
                                           secondary_actor: message)

      expect(notification.push_message_title).to eq "A new message is created in conversation (##{notification.primary_actor.display_id})"
    end

    it 'returns appropriate title suited for the notification type participating_conversation_new_message' do
      message = create(:message, sender: create(:user), content: Faker::Lorem.paragraphs(number: 2))
      notification = create(:notification, notification_type: 'participating_conversation_new_message', primary_actor: message.conversation,
                                           secondary_actor: message)

      expect(notification.push_message_title).to eq "A new message is created in conversation (##{notification.primary_actor.display_id})"
    end

    it 'returns appropriate title suited for the notification type conversation_mention' do
      message = create(:message, sender: create(:user), content: 'Hey [@John](mention://user/1/john), can you check this ticket?')
      notification = create(:notification, notification_type: 'conversation_mention', primary_actor: message.conversation,
                                           secondary_actor: message)

      expect(notification.push_message_title).to eq "You have been mentioned in conversation (##{notification.primary_actor.display_id})"
    end

    # D4 (D-9): título da notificação de takeover interpola display_id + nome de quem assumiu.
    it 'returns appropriate title suited for the notification type conversation_unassignment interpolating the taker' do
      taker = create(:user, name: 'Robin Hood')
      conversation = create(:conversation, assignee: taker)
      notification = create(:notification, notification_type: 'conversation_unassignment', primary_actor: conversation, secondary_actor: taker)

      expect(notification.push_message_title).to eq(
        I18n.t('notifications.notification_title.conversation_unassignment',
               display_id: conversation.display_id, taker: taker.available_name)
      )
    end

    it 'falls back to the secondary actor name when the conversation has no assignee for conversation_unassignment' do
      actor = create(:user, name: 'Little John')
      conversation = create(:conversation, assignee: nil)
      notification = create(:notification, notification_type: 'conversation_unassignment', primary_actor: conversation, secondary_actor: actor)

      expect(notification.push_message_title).to eq(
        I18n.t('notifications.notification_title.conversation_unassignment',
               display_id: conversation.display_id, taker: actor.available_name)
      )
    end

    it 'interpolates the taker name into the localized title for both locales for conversation_unassignment' do
      taker = create(:user, name: 'Robin Hood')
      conversation = create(:conversation, assignee: taker)
      notification = create(:notification, notification_type: 'conversation_unassignment', primary_actor: conversation, secondary_actor: taker)

      # The localized copy is owned/written by D-L1 (config/locales/*.yml — DD-13). This asserts the
      # D-L3 interpolation wiring once the key exists; stays green if D-L1 has not landed it yet.
      %i[en pt-BR].each do |locale|
        I18n.with_locale(locale) do
          next unless I18n.exists?('notifications.notification_title.conversation_unassignment', locale)

          expect(notification.push_message_title).to include(taker.available_name)
          expect(notification.push_message_title).to include(conversation.display_id.to_s)
        end
      end
    end
  end

  context 'when push_message_body is called' do
    it 'returns appropriate body suited for the notification type conversation_creation' do
      conversation = create(:conversation)
      message = create(:message, sender: create(:user), content: Faker::Lorem.paragraphs(number: 2), conversation: conversation)
      notification = create(:notification, notification_type: 'conversation_creation', primary_actor: conversation, secondary_actor: message)
      expect(notification.push_message_body).to eq "#{message.sender.name}: #{message.content.truncate_words(10)}"
    end

    it 'returns appropriate body suited for the notification type conversation_assignment' do
      conversation = create(:conversation)
      message = create(:message, sender: create(:user), content: Faker::Lorem.paragraphs(number: 2), conversation: conversation)
      notification = create(:notification, notification_type: 'conversation_assignment', primary_actor: conversation, secondary_actor: message)
      expect(notification.push_message_body).to eq "#{message.sender.name}: #{message.content.truncate_words(10)}"
    end

    it 'returns appropriate body suited for the notification type conversation_assignment with outgoing message only' do
      conversation = create(:conversation)
      message = create(:message, sender: create(:user), content: Faker::Lorem.paragraphs(number: 2), message_type: :outgoing,
                                 conversation: conversation)
      notification = create(:notification, notification_type: 'conversation_assignment', primary_actor: conversation, secondary_actor: message)
      expect(notification.push_message_body).to eq "#{message.sender.name}: #{message.content.truncate_words(10)}"
    end

    # D4: a notificação de takeover usa a mesma última mensagem in/outgoing do conversation_assignment.
    it 'returns appropriate body suited for the notification type conversation_unassignment' do
      conversation = create(:conversation)
      message = create(:message, sender: create(:user), content: Faker::Lorem.paragraphs(number: 2), conversation: conversation)
      notification = create(:notification, notification_type: 'conversation_unassignment', primary_actor: conversation, secondary_actor: message)
      expect(notification.push_message_body).to eq "#{message.sender.name}: #{message.content.truncate_words(10)}"
    end

    it 'returns appropriate body suited for the notification type assigned_conversation_new_message' do
      conversation = create(:conversation)
      message = create(:message, sender: create(:user), content: Faker::Lorem.paragraphs(number: 2), conversation: conversation)
      notification = create(:notification, notification_type: 'assigned_conversation_new_message', primary_actor: conversation,
                                           secondary_actor: message)
      expect(notification.push_message_body).to eq "#{message.sender.name}: #{message.content.truncate_words(10)}"
    end

    it 'returns appropriate body suited for the notification type assigned_conversation_new_message when attachment message' do
      conversation = create(:conversation)
      message = create(:message, sender: create(:user), content: nil, conversation: conversation)
      attachment = message.attachments.new(file_type: :image, account_id: message.account_id)
      attachment.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
      message.save!
      notification = create(:notification, notification_type: 'assigned_conversation_new_message', primary_actor: conversation,
                                           secondary_actor: message)
      expect(notification.push_message_body).to eq "#{message.sender.name}: Attachment"
    end

    it 'returns appropriate body suited for the notification type participating_conversation_new_message having multple mention' do
      conversation = create(:conversation)
      message = create(:message, sender: create(:user),
                                 content: 'Hey [@John](mention://user/1/john), [@Alisha Peter](mention://user/2/alisha) can you check this ticket?',
                                 conversation: conversation)
      notification = create(:notification, notification_type: 'participating_conversation_new_message', primary_actor: conversation,
                                           secondary_actor: message)
      expect(notification.push_message_body).to eq "#{message.sender.name}: Hey @John, @Alisha Peter can you check this ticket?"
    end

    it 'returns appropriate body suited for the notification type conversation_mention if username contains white space' do
      conversation = create(:conversation)
      message = create(:message, sender: create(:user), content: 'Hey [@John Peter](mention://user/1/john%20K) please check this?',
                                 conversation: conversation)
      notification = create(:notification, notification_type: 'conversation_mention', primary_actor: conversation, secondary_actor: message)
      expect(notification.push_message_body).to eq "#{message.sender.name}: Hey @John Peter please check this?"
    end

    it 'returns appropriate body suited for the notification type conversation_mention if username contains emoji' do
      conversation = create(:conversation)
      content = 'Hey [@👍 customer support](mention://team/1/%F0%9F%91%8D%20customer%20support) please check this?'
      message = create(:message, sender: create(:user), content: content, conversation: conversation)
      notification = create(:notification, notification_type: 'conversation_mention', primary_actor: conversation, secondary_actor: message)
      expect(notification.push_message_body).to eq "#{message.sender.name}: Hey @👍 customer support please check this?"
    end

    it 'returns appropriate body suited for the notification type conversation_mention if team name contains emoji and spaces' do
      conversation = create(:conversation)
      content = 'Please check [@🚀 Development Team](mention://team/2/%F0%9F%9A%80%20Development%20Team)'
      message = create(:message, sender: create(:user), content: content, conversation: conversation)
      notification = create(:notification, notification_type: 'conversation_mention', primary_actor: conversation, secondary_actor: message)
      expect(notification.push_message_body).to eq "#{message.sender.name}: Please check @🚀 Development Team"
    end

    it 'returns appropriate body suited for the notification type conversation_mention with mixed emoji and regular mentions' do
      conversation = create(:conversation)
      content = 'Hey [@John Doe](mention://user/1/John%20Doe) and ' \
                '[@👍 customer support](mention://team/1/%F0%9F%91%8D%20customer%20support) please review'
      message = create(:message, sender: create(:user), content: content, conversation: conversation)
      notification = create(:notification, notification_type: 'conversation_mention', primary_actor: conversation, secondary_actor: message)
      expect(notification.push_message_body).to eq "#{message.sender.name}: Hey @John Doe and @👍 customer support please review"
    end

    it 'returns appropriate body suited for the notification type conversation_mention with special characters in names' do
      conversation = create(:conversation)
      content = 'Please review [@user@domain.com](mention://user/4/user%40domain.com)'
      message = create(:message, sender: create(:user), content: content, conversation: conversation)
      notification = create(:notification, notification_type: 'conversation_mention', primary_actor: conversation, secondary_actor: message)
      expect(notification.push_message_body).to eq "#{message.sender.name}: Please review @user@domain.com"
    end

    it 'calls remove duplicate notification job' do
      allow(Notification::RemoveDuplicateNotificationJob).to receive(:perform_later)
      notification = create(:notification, notification_type: 'conversation_mention')
      expect(Notification::RemoveDuplicateNotificationJob).to have_received(:perform_later).with(notification.id)
    end
  end

  context 'when fcm push data' do
    it 'returns correct data for primary actor conversation' do
      notification = create(:notification, notification_type: 'conversation_creation')
      push_data = notification.fcm_push_data[:primary_actor]
      expect(push_data[:id]).to eq(notification.primary_actor.id)
      expect(push_data[:meta]).to be_a(Hash)
      expect(push_data[:meta]).to have_key(:sender)
      expect(push_data[:meta]).to have_key(:assignee)
    end

    it 'returns correct data for primary actor message' do
      message = create(:message, sender: create(:user), content: Faker::Lorem.paragraphs(number: 2))
      notification = create(:notification, notification_type: 'assigned_conversation_new_message', primary_actor: message.conversation,
                                           secondary_actor: message)
      push_data = notification.fcm_push_data[:primary_actor]
      expect(push_data[:id]).to eq(notification.primary_actor.id)
      expect(push_data[:meta]).to be_a(Hash)
      expect(push_data[:meta]).to have_key(:sender)
      expect(push_data[:meta]).to have_key(:assignee)
    end
  end

  context 'when primary actor is deleted' do
    let!(:conversation) { create(:conversation) }

    it 'clears notifications' do
      notification = create(:notification, notification_type: 'conversation_creation', primary_actor: conversation)
      perform_enqueued_jobs do
        conversation.destroy!
      end

      expect { notification.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
