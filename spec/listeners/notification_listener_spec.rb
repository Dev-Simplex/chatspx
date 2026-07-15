require 'rails_helper'
describe NotificationListener do
  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }
  let!(:first_agent) { create(:user, account: account) }
  let!(:agent_with_out_notification) { create(:user, account: account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: user) }

  describe 'conversation_created' do
    let(:event_name) { :'conversation.created' }

    context 'when conversation is created' do
      it 'creates notifications for inbox members who have notifications turned on' do
        notification_setting = first_agent.notification_settings.first
        notification_setting.selected_email_flags = [:email_conversation_creation]
        notification_setting.selected_push_flags = []
        notification_setting.save!

        create(:inbox_member, user: first_agent, inbox: inbox)
        conversation.reload

        event = Events::Base.new(event_name, Time.zone.now, conversation: conversation)

        listener.conversation_created(event)
        expect(notification_setting.user.notifications.count).to eq(1)
      end

      it 'does not create notification for inbox members who have notifications turned off' do
        notification_setting = agent_with_out_notification.notification_settings.first
        notification_setting.unselect_all_email_flags
        notification_setting.unselect_all_push_flags
        notification_setting.save!

        create(:inbox_member, user: agent_with_out_notification, inbox: inbox)
        conversation.reload

        event = Events::Base.new(event_name, Time.zone.now, conversation: conversation)

        listener.conversation_created(event)
        expect(notification_setting.user.notifications.count).to eq(0)
      end
    end

    # A audiência do sino segue a mesma regra da LISTA de conversas: membro do inbox E
    # (conversa sem time OU time do usuário). Agente sem time nenhum não é filtrado por time.
    context 'when the conversation already belongs to a team' do
      let!(:team_x) { create(:team, account: account) }
      let!(:team_y) { create(:team, account: account) }
      let!(:team_conversation) { create(:conversation, account: account, inbox: inbox, team: team_x) }

      def opt_in(user)
        setting = user.notification_settings.first
        setting.selected_email_flags = [:email_conversation_creation]
        setting.selected_push_flags = []
        setting.save!
      end

      def dispatch
        listener.conversation_created(
          Events::Base.new(event_name, Time.zone.now, conversation: team_conversation.reload)
        )
      end

      it 'does not notify an inbox member from another team' do
        opt_in(first_agent)
        create(:inbox_member, user: first_agent, inbox: inbox)
        create(:team_member, user: first_agent, team: team_y)

        dispatch

        expect(first_agent.notifications.count).to eq(0)
      end

      it 'notifies an inbox member of the same team' do
        opt_in(first_agent)
        create(:inbox_member, user: first_agent, inbox: inbox)
        create(:team_member, user: first_agent, team: team_x)

        dispatch

        expect(first_agent.notifications.count).to eq(1)
      end

      it 'notifies an inbox member without any team' do
        opt_in(first_agent)
        create(:inbox_member, user: first_agent, inbox: inbox)

        dispatch

        expect(first_agent.notifications.count).to eq(1)
      end

      it 'notifies an administrator from another team' do
        admin = create(:user, account: account, role: :administrator)
        opt_in(admin)
        create(:inbox_member, user: admin, inbox: inbox)
        create(:team_member, user: admin, team: team_y)

        dispatch

        expect(admin.notifications.count).to eq(1)
      end
    end
  end

  describe 'message_created' do
    let(:event_name) { :'message.created' }

    before do
      notification_setting = first_agent.notification_settings.find_by(account_id: account.id)
      notification_setting.selected_email_flags = [:email_conversation_mention]
      notification_setting.selected_push_flags = []
      notification_setting.save!
    end

    it 'will call mention service' do
      mention_service = instance_double(Messages::MentionService)
      allow(Messages::MentionService).to receive(:new).and_return(mention_service)
      allow(mention_service).to receive(:perform)

      create(:inbox_member, user: first_agent, inbox: inbox)
      conversation.reload

      message = build(
        :message,
        conversation: conversation,
        account: account,
        content: "hi [#{first_agent.name}](mention://user/#{first_agent.id}/#{first_agent.name})",
        private: true
      )

      expect(mention_service).to receive(:perform)
      event = Events::Base.new(event_name, Time.zone.now, message: message)
      listener.message_created(event)
    end

    it 'will call new message notification service' do
      notification_service = instance_double(Messages::NewMessageNotificationService)
      allow(Messages::NewMessageNotificationService).to receive(:new).and_return(notification_service)
      allow(notification_service).to receive(:perform)

      create(:inbox_member, user: first_agent, inbox: inbox)
      conversation.reload

      message = build(
        :message,
        conversation: conversation,
        account: account,
        content: 'hi',
        private: true
      )

      expect(notification_service).to receive(:perform)
      event = Events::Base.new(event_name, Time.zone.now, message: message)
      listener.message_created(event)
    end

    context 'when message content is empty' do
      it 'will be processed correctly' do
        builder = double
        allow(NotificationBuilder).to receive(:new).and_return(builder)
        allow(builder).to receive(:perform)

        create(:inbox_member, user: first_agent, inbox: inbox)
        conversation.reload

        message = build(
          :message,
          conversation: conversation,
          account: account,
          content: nil,
          private: true
        )

        event = Events::Base.new(event_name, Time.zone.now, message: message)
        # want to validate message_created doesnt throw an error
        expect { listener.message_created(event) }.not_to raise_error
      end
    end
  end

  # integration tests to ensure that the order mention service and new message notification service are called in the correct order
  describe 'message_created - mentions, participation & assignment integration' do
    let(:event_name) { :'message.created' }

    it 'will not create duplicate new message notification for the same user for mentions participation & assignment' do
      create(:inbox_member, user: first_agent, inbox: inbox)
      conversation.update(assignee: first_agent)

      message = build(
        :message,
        conversation: conversation,
        account: account,
        content: "hi [#{first_agent.name}](mention://user/#{first_agent.id}/#{first_agent.name})",
        private: true
      )
      event = Events::Base.new(event_name, Time.zone.now, message: message)
      listener.message_created(event)

      expect(first_agent.notifications.count).to eq(1)
      expect(first_agent.notifications.first.notification_type).to eq('conversation_mention')
    end

    it 'will create a mention notification when a user is mentioned in a private note' do
      create(:inbox_member, user: first_agent, inbox: inbox)

      message = build(
        :message,
        conversation: conversation,
        account: account,
        content: "hey [#{first_agent.name}](mention://user/#{first_agent.id}/#{first_agent.name})",
        private: true
      )
      event = Events::Base.new(event_name, Time.zone.now, message: message)
      listener.message_created(event)

      expect(first_agent.notifications.count).to eq(1)
      expect(first_agent.notifications.first.notification_type).to eq('conversation_mention')
    end

    it 'will not create new message notifications for private messages without mentions' do
      create(:inbox_member, user: first_agent, inbox: inbox)
      conversation.update(assignee: first_agent)
      # participants is created by async job. so creating it directly for testcase
      conversation.conversation_participants.first_or_create(user: first_agent)

      message = build(
        :message,
        conversation: conversation,
        account: account,
        content: 'hi',
        private: true
      )

      event = Events::Base.new(event_name, Time.zone.now, message: message)
      listener.message_created(event)

      expect(conversation.conversation_participants.map(&:user)).to include(first_agent)
      expect(first_agent.notifications.count).to eq(0)
    end
  end

  describe 'conversation_bot_handoff' do
    let(:event_name) { :'conversation.bot_handoff' }

    context 'when conversation is bot handoff' do
      it 'creates notifications for inbox members who have notifications turned on' do
        notification_setting = first_agent.notification_settings.first
        notification_setting.selected_email_flags = [:email_conversation_creation]
        notification_setting.selected_push_flags = []
        notification_setting.save!

        create(:inbox_member, user: first_agent, inbox: inbox)
        conversation.reload

        event = Events::Base.new(event_name, Time.zone.now, conversation: conversation)

        listener.conversation_bot_handoff(event)
        expect(notification_setting.user.notifications.count).to eq(1)
      end

      it 'does not create notification for inbox members who have notifications turned off' do
        notification_setting = agent_with_out_notification.notification_settings.first
        notification_setting.unselect_all_email_flags
        notification_setting.unselect_all_push_flags
        notification_setting.save!

        create(:inbox_member, user: agent_with_out_notification, inbox: inbox)
        conversation.reload

        event = Events::Base.new(event_name, Time.zone.now, conversation: conversation)

        listener.conversation_bot_handoff(event)
        expect(notification_setting.user.notifications.count).to eq(0)
      end
    end
  end

  describe 'assignee_changed' do
    let(:event_name) { :'conversation.assignee_changed' }

    context 'when notifiable_assignee_change is true but assignee is nil' do
      it 'does not create a notification' do
        conversation_with_nil_assignee = create(:conversation, account: account, inbox: inbox, assignee: nil)

        notification_builder_mock = instance_double(NotificationBuilder)
        allow(NotificationBuilder).to receive(:new).and_return(notification_builder_mock)

        event = Events::Base.new(
          event_name,
          Time.zone.now,
          conversation: conversation_with_nil_assignee,
          data: { notifiable_assignee_change: true }
        )

        expect(notification_builder_mock).not_to receive(:perform)

        listener.assignee_changed(event)
      end
    end
  end

  # D4 (D-9): notifica quem PERDEU a conversa quando outro agente assume (takeover).
  describe 'assignee_changed - conversation_unassignment (D4)' do
    let(:event_name) { :'conversation.assignee_changed' }
    let!(:old_assignee) { create(:user, account: account) }
    let!(:new_assignee) { create(:user, account: account) }

    # O ator REAL chega pelo event data (capturado no dispatch sync). No worker async Current.user é
    # NIL — por isso TODOS os exemplos rodam com Current.user = nil, exercitando o caminho de produção.
    before { Current.user = nil }
    after { Current.user = nil }

    def assignee_changed_event(conversation, old_id:, new_id:, actor: nil, notifiable: false)
      Events::Base.new(
        event_name,
        Time.zone.now,
        conversation: conversation,
        notifiable_assignee_change: notifiable,
        changed_attributes: { 'assignee_id' => [old_id, new_id] },
        assignee_changed_by: actor
      )
    end

    context 'when the reply assignment gate is enabled' do
      before { account.update!(settings: account.settings.merge('reply_assignment_gate' => true)) }

      it 'notifies the previous assignee on a self-assign takeover (D-9 robbery)' do
        # B robs the conversation from A: notifiable_assignee_change is false (self-assign)
        conversation.update!(assignee: new_assignee)
        event = assignee_changed_event(conversation, old_id: old_assignee.id, new_id: new_assignee.id,
                                                     actor: new_assignee, notifiable: false)

        listener.assignee_changed(event)

        expect(old_assignee.notifications.where(notification_type: 'conversation_unassignment').count).to eq(1)
        notification = old_assignee.notifications.last
        expect(notification.primary_actor).to eq(conversation)
        # secondary_actor vem do event data (Current.user é nil no worker) — não cai mais para nil
        expect(notification.secondary_actor).to eq(new_assignee)
        # the robber (the actor) is NOT notified of an assignment (self-assign guard upstream)
        expect(new_assignee.notifications.where(notification_type: 'conversation_assignment').count).to eq(0)
      end

      it 'notifies the previous assignee AND the new assignee on an admin reassignment' do
        admin = create(:user, account: account, role: :administrator)
        conversation.update!(assignee: new_assignee)
        event = assignee_changed_event(conversation, old_id: old_assignee.id, new_id: new_assignee.id,
                                                     actor: admin, notifiable: true)

        listener.assignee_changed(event)

        expect(old_assignee.notifications.where(notification_type: 'conversation_unassignment').count).to eq(1)
        expect(new_assignee.notifications.where(notification_type: 'conversation_assignment').count).to eq(1)
      end

      it 'does not notify when old assignee equals new assignee' do
        event = assignee_changed_event(conversation, old_id: old_assignee.id, new_id: old_assignee.id, actor: new_assignee)

        listener.assignee_changed(event)

        expect(old_assignee.notifications.where(notification_type: 'conversation_unassignment')).to be_empty
      end

      it 'does not notify when the conversation was previously orphaned (old id nil)' do
        event = assignee_changed_event(conversation, old_id: nil, new_id: new_assignee.id, actor: new_assignee)

        listener.assignee_changed(event)

        expect(Notification.where(notification_type: 'conversation_unassignment')).to be_empty
      end

      it 'does not notify when the conversation became orphaned (new id nil)' do
        event = assignee_changed_event(conversation, old_id: old_assignee.id, new_id: nil, actor: old_assignee)

        listener.assignee_changed(event)

        expect(old_assignee.notifications.where(notification_type: 'conversation_unassignment')).to be_empty
      end

      it 'does not notify when the previous assignee released the conversation themselves' do
        # A solta a própria conversa: o ator (event data) é A == old_id -> auto-desatribuição, no-op
        event = assignee_changed_event(conversation, old_id: old_assignee.id, new_id: new_assignee.id, actor: old_assignee)

        listener.assignee_changed(event)

        expect(old_assignee.notifications.where(notification_type: 'conversation_unassignment')).to be_empty
      end

      it 'does not notify when the previous assignee is no longer in the account' do
        event = assignee_changed_event(conversation, old_id: 0, new_id: new_assignee.id, actor: new_assignee)

        listener.assignee_changed(event)

        expect(Notification.where(notification_type: 'conversation_unassignment')).to be_empty
      end

      it 'does not notify when the conversation is pending' do
        conversation.update_columns(status: :pending) # rubocop:disable Rails/SkipsModelValidations
        event = assignee_changed_event(conversation.reload, old_id: old_assignee.id, new_id: new_assignee.id, actor: new_assignee)

        listener.assignee_changed(event)

        expect(old_assignee.notifications.where(notification_type: 'conversation_unassignment')).to be_empty
      end

      # Caminho async REAL (vigia-telemetria-e): driva o callback chain e o EventDispatcherJob com
      # Current.user LIMPO dentro do worker — onde o guard antigo (Current.user) estava morto.
      # perform_enqueued_jobs envolve SÓ o update (não o setup das factories, que dispara avatar jobs).
      context 'when dispatched through the async worker (Current.user nil in the worker)' do
        # Captura o ator no dispatch sync (Current.user = by), depois LIMPA Current.user e só então
        # roda o EventDispatcherJob — reproduzindo o worker async, onde Current.user é NIL. O guard e o
        # secondary_actor precisam funcionar a partir do event data, não de Current.user.
        def reassign_through_worker(to:, by:)
          Current.user = by
          conversation.update!(assignee: to) # after_commit enfileira o EventDispatcherJob (captura o ator)
          Current.user = nil
          perform_enqueued_jobs(only: EventDispatcherJob) # worker roda aqui, com Current.user já limpo
        end

        before do
          conversation.update!(assignee: old_assignee)
          old_assignee.notifications.where(notification_type: 'conversation_unassignment').delete_all
          clear_enqueued_jobs # descarta jobs do setup; o teste só performa o EventDispatcherJob do reassign
        end

        it 'does NOT notify when an agent reassigns their OWN conversation (no spurious notification)' do
          # A é o dono e reatribui a própria conversa para B; o ator real (A) == old_id -> no-op.
          reassign_through_worker(to: new_assignee, by: old_assignee)

          expect(old_assignee.notifications.where(notification_type: 'conversation_unassignment')).to be_empty
        end

        it 'notifies the previous assignee when a colleague takes the conversation over' do
          # A é o dono; B (colega) assume. O ator real (B) != old_id (A) -> A é notificado.
          reassign_through_worker(to: new_assignee, by: new_assignee)

          notification = old_assignee.notifications.where(notification_type: 'conversation_unassignment').last
          expect(notification).to be_present
          expect(notification.secondary_actor).to eq(new_assignee)
        end
      end
    end

    context 'when the reply assignment gate is disabled (Classic)' do
      it 'does not notify the previous assignee' do
        event = assignee_changed_event(conversation, old_id: old_assignee.id, new_id: new_assignee.id, actor: new_assignee)

        listener.assignee_changed(event)

        expect(old_assignee.notifications.where(notification_type: 'conversation_unassignment')).to be_empty
      end
    end
  end
end
