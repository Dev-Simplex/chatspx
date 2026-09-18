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

  # F-1: so um HUMANO assumindo a conversa cancela a pesquisa. `outgoing` sozinho tambem cobria a
  # IA do Captain, o flow, a regra de automacao e o template de disparo — 1.541 das 3.181 pesquisas
  # descartadas da base (48%) morreram assim, e a nota que o cliente mandava depois caia no vazio,
  # porque o ResponseBuilder so age sobre status `sent`.
  describe '#message_created' do
    let(:agente) { create(:user, account: account, role: :agent) }

    let!(:pesquisa) do
      create(:nps_response, conversation: conversation, status: 'sent',
                            score: nil, answered_at: nil, sent_at: 5.minutes.ago)
    end

    def deliver(message)
      listener.message_created(Events::Base.new('message_created', Time.zone.now, { message: message }))
    end

    def outgoing(sender: nil, content_attributes: {}, private_note: false)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                       content: 'oi', sender: sender, private: private_note, content_attributes: content_attributes)
    end

    it 'dismisses the survey when a human agent replies' do
      deliver(outgoing(sender: agente))

      expect(pesquisa.reload.status).to eq('dismissed')
    end

    it 'keeps the survey when the AI answers' do
      deliver(outgoing(sender: create(:agent_bot)))

      expect(pesquisa.reload.status).to eq('sent')
    end

    it 'keeps the survey when a flow answers' do
      deliver(outgoing(content_attributes: { 'flow_id' => 7 }))

      expect(pesquisa.reload.status).to eq('sent')
    end

    it 'keeps the survey when an automation rule answers' do
      deliver(outgoing(sender: agente, content_attributes: { 'automation_rule_id' => 3 }))

      expect(pesquisa.reload.status).to eq('sent')
    end

    # Nota privada e conversa interna: o cliente nao ve, entao ninguem assumiu o atendimento.
    it 'keeps the survey when the human writes a private note' do
      deliver(outgoing(sender: agente, private_note: true))

      expect(pesquisa.reload.status).to eq('sent')
    end

    # Guarda antiga que continua valendo: as mensagens do proprio fluxo NPS nao se cancelam.
    it 'keeps the survey when the NPS flow itself sends a message' do
      deliver(outgoing(sender: agente, content_attributes: { 'nps_survey_system' => true }))

      expect(pesquisa.reload.status).to eq('sent')
    end
  end
end
