require 'rails_helper'

# CHAT-174: a Message criada pelo SendService já enfileira o SendReplyJob no callback de criação
# (Message#send_reply). Um segundo perform_later explícito fazia o canal receber a mesma mensagem
# duas vezes — inclusive template pago.
RSpec.describe ScheduledMessages::SendService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:user) { create(:user, account: account, role: :agent) }

  def envios_enfileirados
    ActiveJob::Base.queue_adapter.enqueued_jobs.count { |job| job['job_class'] == 'SendReplyJob' }
  end

  it 'enfileira um único envio ao canal para a mensagem que cria' do
    scheduled = ScheduledMessage.create!(conversation: conversation, inbox: inbox, message: 'Oi', scheduled_at: 1.minute.from_now,
                                         status: :pending, scheduled_by: user)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    message = described_class.new(scheduled_message: scheduled).perform

    expect(message).to be_persisted
    expect(envios_enfileirados).to eq(1)
    expect(scheduled.reload).to be_sent
  end

  it 'continua enfileirando o envio quando a mensagem já existia' do
    existente = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                                 sender: user, content: 'Oi')
    scheduled = ScheduledMessage.create!(conversation: conversation, inbox: inbox, message: 'Oi', scheduled_at: 1.minute.from_now,
                                         status: :pending, scheduled_by: user, message_id: existente.id)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    described_class.new(scheduled_message: scheduled).perform

    expect(envios_enfileirados).to eq(1)
    expect(scheduled.reload).to be_sent
  end
end
