require 'rails_helper'

describe MessageTemplates::Template::OutOfOffice do
  context 'when this hook is called' do
    let(:conversation) { create(:conversation) }

    it 'creates the out of office messages' do
      described_class.new(conversation: conversation).perform
      expect(conversation.messages.template.count).to eq(1)
      expect(conversation.messages.template.first.content).to eq(conversation.inbox.out_of_office_message)
    end

    it 'creates the out of office messages with template variable' do
      conversation.inbox.update!(out_of_office_message: 'Hey, {{contact.name}} we are unavailable at the moment.')
      described_class.new(conversation: conversation).perform
      expect(conversation.messages.count).to eq(1)
      expect(conversation.messages.last.content).to eq("Hey, #{conversation.contact.name} we are unavailable at the moment.")
    end

    it 'creates the out of office messages with more than one variable strings' do
      conversation.inbox.update!(out_of_office_message:
        'Hey, {{contact.name}} we are unavailable at the moment. - from {{account.name}}')
      described_class.new(conversation: conversation).perform
      expect(conversation.messages.count).to eq(1)
      expect(conversation.messages.last.content).to eq(
        "Hey, #{conversation.contact.name} we are unavailable at the moment. - from #{conversation.account.name}"
      )
    end
  end

  # .perform_if_applicable e o gate usado pelos caminhos do Captain (handoff, response builder,
  # resolucao de pendentes). Sem o freio aqui, esses 4 chamadores furariam o guard do
  # HookExecutionService e o texto de fora-de-horario voltaria a cair dentro do grupo.
  describe '.perform_if_applicable' do
    let(:inbox) { create(:inbox, out_of_office_message: 'We are out of office') }

    before do
      inbox.update!(working_hours_enabled: true)
      inbox.working_hours.today.update!(closed_all_day: true)
    end

    it 'sends the out of office message on a 1:1 conversation' do
      conversation = create(:conversation, inbox: inbox)

      described_class.perform_if_applicable(conversation)

      expect(conversation.messages.template.count).to eq(1)
    end

    it 'does not send it on a WhatsApp group conversation' do
      group_contact = create(:contact, account: inbox.account, identifier: '5566999991234-1634750731@g.us')
      conversation = create(:conversation, inbox: inbox, contact: group_contact)

      described_class.perform_if_applicable(conversation)

      expect(conversation.messages.template.count).to eq(0)
    end
  end
end
