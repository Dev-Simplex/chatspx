require 'rails_helper'

describe NpsSurveyListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, nps_survey_enabled: true, nps_config: { 'mode' => 'auto' }) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, status: :resolved)
  end
  let(:event) { Events::Base.new('conversation.status_changed', Time.zone.now, conversation: conversation) }
  let(:nps_service) { instance_double(NpsSurveyService, perform: true) }

  before do
    allow(NpsSurveyService).to receive(:new).and_return(nps_service)
  end

  describe '#conversation_status_changed' do
    context 'when the conversation is 1:1' do
      it 'sends the automatic NPS survey' do
        listener.conversation_status_changed(event)

        expect(NpsSurveyService).to have_received(:new).with(conversation: conversation, mode: 'auto')
        expect(nps_service).to have_received(:perform)
      end
    end

    # Freio de GRUPO: 2 NpsResponse ja foram gravadas dentro de conversas de grupo nesta base.
    # A pesquisa e sobre UM atendimento com UM cliente; num grupo qualquer participante responde
    # por todos. Ver Conversation#group? (ponto unico de verdade).
    context 'when the conversation is a WhatsApp group' do
      it 'does not send the survey when the contact identifier ends with @g.us' do
        contact.update!(identifier: '5566999991234-1634750731@g.us')

        listener.conversation_status_changed(event)

        expect(NpsSurveyService).not_to have_received(:new)
      end

      it 'does not send the survey when additional_attributes flags the group' do
        conversation.update!(additional_attributes: { 'type' => 'group' })

        listener.conversation_status_changed(event)

        expect(NpsSurveyService).not_to have_received(:new)
      end

      it 'does not send the survey when waha_whatsapp_chat_id ends with @g.us' do
        contact.update!(custom_attributes: { 'waha_whatsapp_chat_id' => '120363000000000000@g.us' })

        listener.conversation_status_changed(event)

        expect(NpsSurveyService).not_to have_received(:new)
      end
    end

    context 'when the conversation is not resolved' do
      it 'does not send the survey' do
        conversation.update!(status: :open)

        listener.conversation_status_changed(event)

        expect(NpsSurveyService).not_to have_received(:new)
      end
    end

    context 'when the inbox has NPS disabled' do
      it 'does not send the survey' do
        inbox.update!(nps_survey_enabled: false)

        listener.conversation_status_changed(event)

        expect(NpsSurveyService).not_to have_received(:new)
      end
    end
  end
end
