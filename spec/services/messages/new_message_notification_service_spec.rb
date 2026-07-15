require 'rails_helper'

describe Messages::NewMessageNotificationService do
  context 'when message is not notifiable' do
    it 'will not create any notifications for activity messages' do
      message = build(:message, message_type: :activity)
      expect(NotificationBuilder).not_to receive(:new)
      described_class.new(message: message).perform
    end

    it 'will not create any notifications for private messages' do
      message = build(:message, message_type: :outgoing, private: true)
      expect(NotificationBuilder).not_to receive(:new)
      described_class.new(message: message).perform
    end
  end

  # Regra canônica: notificar U sobre mensagem nova em C  <=>  U == C.assignee.
  # A participação é ETERNA (o ParticipationListener adiciona todo assignee e nunca remove o
  # anterior), então notificar participantes fazia o sino tocar para todo mundo que um dia encostou
  # na conversa. A aba "Participantes da conversa" continua sendo alimentada, mas é só informativa.
  context 'when message is notifiable' do
    let(:account) { create(:account) }
    let(:assignee) { create(:user, account: account) }
    let(:participating_agent_1) { create(:user, account: account) }
    let(:participating_agent_2) { create(:user, account: account) }
    let(:participating_admin) { create(:user, account: account, role: :administrator) }
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: assignee) }

    before do
      [participating_agent_1, participating_agent_2, participating_admin, assignee].each do |user|
        create(:inbox_member, inbox: inbox, user: user)
        create(:conversation_participant, conversation: conversation, user: user)
      end
    end

    context 'when message is created by a contact' do
      let(:message) { create(:message, conversation: conversation, account: account) }

      before do
        described_class.new(message: message).perform
      end

      it 'creates a notification for the assignee' do
        expect(assignee.notifications.where(notification_type: 'assigned_conversation_new_message', account: account,
                                            primary_actor: message.conversation, secondary_actor: message)).to exist
      end

      it 'does not notify a participant who is not the assignee' do
        expect(participating_agent_1.notifications.where(primary_actor: message.conversation)).not_to exist
        expect(participating_agent_2.notifications.where(primary_actor: message.conversation)).not_to exist
      end

      # D4: o admin não é exceção. O dono é admin e pediu MENOS ruído, não mais.
      it 'does not notify a participating administrator' do
        expect(participating_admin.notifications.where(primary_actor: message.conversation)).not_to exist
      end

      it 'notifies the assignee and nobody else' do
        expect(Notification.where(primary_actor: message.conversation).pluck(:user_id)).to contain_exactly(assignee.id)
      end
    end

    context 'when message is created by a participant' do
      let(:message) { create(:message, conversation: conversation, account: account, sender: participating_agent_1) }

      before do
        described_class.new(message: message).perform
      end

      it 'creates a notification for the assignee' do
        expect(assignee.notifications.where(notification_type: 'assigned_conversation_new_message', account: account,
                                            primary_actor: message.conversation, secondary_actor: message)).to exist
      end

      it 'does not notify the other participants' do
        expect(participating_agent_2.notifications.where(primary_actor: message.conversation)).not_to exist
      end

      it 'will not create notifications for the user who created the message' do
        expect(participating_agent_1.notifications.where(primary_actor: message.conversation)).not_to exist
      end
    end

    context 'when message is created by assignee' do
      let(:message) { create(:message, conversation: conversation, account: account, sender: assignee) }

      before do
        described_class.new(message: message).perform
      end

      it 'will not create notifications for the user who created the message' do
        expect(assignee.notifications.where(primary_actor: message.conversation)).not_to exist
      end
    end

    # Guard contra o sino duplicado (o assignee também é participante): mesmo depois de este service
    # criar a notificação do assignee, uma segunda passada não pode gerar outra.
    context 'when the service runs twice for the same message' do
      let(:message) { create(:message, conversation: conversation, account: account) }

      it 'does not notify the assignee twice' do
        2.times { described_class.new(message: message).perform }

        expect(assignee.notifications.where(primary_actor: message.conversation, secondary_actor: message).count).to eq(1)
      end
    end
  end

  # D2: silêncio aceito. A lista de "Não atribuídas" + orphan_retriage_job / queue_escalation_job
  # cobrem esse caso alertando o admin por outro caminho.
  context 'when the conversation has no assignee' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:participant) { create(:user, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
    let(:message) { create(:message, conversation: conversation, account: account) }

    before do
      create(:inbox_member, inbox: inbox, user: participant)
      create(:conversation_participant, conversation: conversation, user: participant)
      described_class.new(message: message).perform
    end

    it 'does not notify anyone' do
      expect(Notification.where(primary_actor: conversation)).not_to exist
    end
  end

  # O assignee sobrevive ao resolve (nada zera assignee_id) e a reabertura não o troca no caso normal,
  # então "notificar o assignee" == "notificar quem estava atribuído quando a conversa foi resolvida".
  context 'when a resolved conversation is reopened by a new message' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:assignee) { create(:user, account: account) }
    let(:ex_assignee) { create(:user, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: assignee) }

    before do
      [assignee, ex_assignee].each { |user| create(:inbox_member, inbox: inbox, user: user) }
      create(:conversation_participant, conversation: conversation, user: ex_assignee)
      conversation.resolved!
    end

    it 'notifies the user who was assigned when it was resolved' do
      message = create(:message, conversation: conversation, account: account, message_type: :incoming)
      described_class.new(message: message).perform

      expect(conversation.reload.open?).to be true
      expect(Notification.where(primary_actor: conversation).pluck(:user_id)).to contain_exactly(assignee.id)
    end

    # Armadilha: o sino lê conversation.assignee. Hoje reopen_conversation roda ANTES de
    # dispatch_create_events (message.rb, ordem explícita por causa de rails/rails#20911). Se alguém
    # reordenar, uma reabertura que reatribua a conversa mandaria o sino para o assignee ANTIGO.
    it 'reopens the conversation before dispatching the create events' do
      message = build(:message, conversation: conversation, account: account, message_type: :incoming)
      call_order = []
      allow(message).to receive(:reopen_conversation).and_wrap_original do |original|
        call_order << :reopen_conversation
        original.call
      end
      allow(message).to receive(:dispatch_create_events).and_wrap_original do |original|
        call_order << :dispatch_create_events
        original.call
      end

      message.save!

      expect(call_order).to eq(%i[reopen_conversation dispatch_create_events])
    end
  end
end
