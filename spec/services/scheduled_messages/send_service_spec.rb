require 'rails_helper'

RSpec.describe ScheduledMessages::SendService do
  let(:account) { create(:account) }
  let(:template_body) { 'Oi {{1}}, voltando no horário combinado. Pode falar agora?' }
  let(:channel) do
    create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false,
                              message_templates: [{ 'name' => 'retomada_combinada', 'status' => 'approved',
                                                    'language' => 'pt_BR', 'category' => 'UTILITY',
                                                    'components' => [{ 'type' => 'BODY', 'text' => template_body }] }])
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, name: 'Maria Souza') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:human) { create(:user, account: account, role: :agent) }
  let(:template_configurado) { { 'name' => 'retomada_combinada', 'language' => 'pt_BR' } }

  def agendada_da_ia(texto: 'E aí, deu certo de conversar?')
    ScheduledMessage.create!(conversation: conversation, inbox: inbox, message: texto,
                             scheduled_at: 1.minute.from_now, status: :pending, captain_assistant_id: assistant.id)
  end

  def cliente_falou(tempo)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     sender: contact, created_at: tempo.ago)
  end

  describe 'agendada escrita pela IA' do
    describe 'com a janela de 24h aberta' do
      before { cliente_falou(2.hours) }

      it 'envia o texto pronto em nome da IA' do
        scheduled = agendada_da_ia
        message = described_class.new(scheduled_message: scheduled).perform

        expect(message.sender).to eq(assistant)
        expect(message.content).to eq('E aí, deu certo de conversar?')
        expect(message.additional_attributes['template_params']).to be_nil
        expect(scheduled.reload).to be_sent
        expect(scheduled.message_id).to eq(message.id)
      end

      it 'envia mesmo com handoff aguardando humano e com humano atribuído' do
        conversation.update!(assignee: human,
                             custom_attributes: { 'aguardando_humano_desde' => 1.hour.ago.iso8601 })
        scheduled = agendada_da_ia
        message = described_class.new(scheduled_message: scheduled).perform

        expect(message.sender).to eq(assistant)
        expect(message.send(:human_response?)).to be(false)
        expect(scheduled.reload).to be_sent
      end
    end

    describe 'com a janela de 24h fechada' do
      before { cliente_falou(30.hours) }

      it 'envia o template configurado no agente, com o primeiro nome do contato' do
        assistant.update!(behavior: { 'agendada' => { 'template_fora_janela' => template_configurado } })
        scheduled = agendada_da_ia
        message = described_class.new(scheduled_message: scheduled).perform

        expect(message.sender).to eq(assistant)
        expect(message.content).to eq('Oi Maria, voltando no horário combinado. Pode falar agora?')
        expect(message.additional_attributes['template_params']).to include(
          'name' => 'retomada_combinada', 'language' => 'pt_BR',
          'processed_params' => { 'body' => { '1' => 'Maria' } }
        )
        expect(scheduled.reload).to be_sent
      end

      it 'não envia e registra na conversa quando o agente não tem template configurado' do
        scheduled = agendada_da_ia
        expect(described_class.new(scheduled_message: scheduled).perform).to be_nil

        expect(scheduled.reload).to be_failed
        expect(scheduled.error_message).to be_present
        expect(conversation.messages.outgoing.count).to eq(0)
        expect(conversation.messages.activity.last&.content).to be_present
      end

      it 'não envia o template quando o contato não tem nome para a variável' do
        contact.update!(name: '')
        assistant.update!(behavior: { 'agendada' => { 'template_fora_janela' => template_configurado } })
        scheduled = agendada_da_ia
        expect(described_class.new(scheduled_message: scheduled).perform).to be_nil

        expect(scheduled.reload).to be_failed
        expect(scheduled.error_message).to eq(I18n.t('scheduled_messages.errors.template_without_contact_name'))
        expect(conversation.messages.outgoing.count).to eq(0)
      end
    end
  end

  describe 'agendada criada por pessoa' do
    it 'continua saindo em nome de quem agendou' do
      cliente_falou(2.hours)
      scheduled = ScheduledMessage.create!(conversation: conversation, inbox: inbox, message: 'Oi',
                                           scheduled_at: 1.minute.from_now, status: :pending, scheduled_by: human)
      message = described_class.new(scheduled_message: scheduled).perform

      expect(message.sender).to eq(human)
      expect(scheduled.reload).to be_sent
    end
  end
end
