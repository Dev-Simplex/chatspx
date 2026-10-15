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

      describe 'com template de duas variáveis' do
        let(:template_body) { 'Oi {{1}}, retomando o que combinamos: {{2}} Pode me responder por aqui?' }

        it 'preenche cada variável pela origem configurada, com o texto pronto numa linha só' do
          assistant.update!(behavior: { 'agendada' => { 'template_fora_janela' => template_configurado.merge(
            'variaveis' => { '1' => 'primeiro_nome', '2' => 'texto' }
          ) } })
          scheduled = agendada_da_ia(texto: "Deu certo de conversar?\n\nSe quiser, marco a visita.")
          message = described_class.new(scheduled_message: scheduled).perform

          expect(message.content).to eq('Oi Maria, retomando o que combinamos: Deu certo de conversar? Se quiser, marco a visita. ' \
                                        'Pode me responder por aqui?')
          expect(message.additional_attributes.dig('template_params', 'processed_params', 'body')).to eq(
            '1' => 'Maria', '2' => 'Deu certo de conversar? Se quiser, marco a visita.'
          )
        end

        it 'não envia quando uma variável do template não tem origem configurada' do
          assistant.update!(behavior: { 'agendada' => { 'template_fora_janela' => template_configurado } })
          scheduled = agendada_da_ia
          expect(described_class.new(scheduled_message: scheduled).perform).to be_nil

          expect(scheduled.reload.error_message).to eq(I18n.t('scheduled_messages.errors.template_unsupported_variables'))
          expect(conversation.messages.outgoing.count).to eq(0)
        end
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
        expect(scheduled.error_message).to eq(I18n.t('scheduled_messages.errors.template_without_primeiro_nome'))
        expect(conversation.messages.outgoing.count).to eq(0)
      end
    end
  end

  describe 'revisão pela IA no horário' do
    let(:agendada) do
      ScheduledMessage.create!(conversation: conversation, inbox: inbox, message: 'Texto pronto', scheduled_at: 1.minute.from_now,
                               status: :pending, captain_assistant_id: assistant.id, created_at: 3.hours.ago)
    end

    before do
      cliente_falou(4.hours)
      conversation.update!(assignee_agent_bot: assistant.mirror_agent_bot)
      allow(Captain::Conversation::ResponseBuilderJob).to receive(:perform_now)
    end

    it 'sem fala nova do cliente, envia o texto pronto sem acionar a IA' do
      message = described_class.new(scheduled_message: agendada).perform

      expect(Captain::Conversation::ResponseBuilderJob).not_to have_received(:perform_now)
      expect(message.content).to eq('Texto pronto')
    end

    context 'when the client wrote after the scheduling and the AI owns the conversation' do
      before { cliente_falou(1.hour) }

      it 'a IA revisa e a mensagem dela é a agendada cumprida' do
        allow(Captain::Conversation::ResponseBuilderJob).to receive(:perform_now) do
          conversation.messages.create!(message_type: :outgoing, account_id: account.id, inbox_id: inbox.id,
                                        sender: assistant, content: 'Texto ajustado')
        end

        message = described_class.new(scheduled_message: agendada).perform

        expect(Captain::Conversation::ResponseBuilderJob).to have_received(:perform_now)
          .with(conversation, assistant, directive: a_string_including('Texto pronto'))
        expect(message.content).to eq('Texto ajustado')
        expect(agendada.reload).to be_sent
      end

      it 'a IA desiste e a agendada fica cancelada com o motivo' do
        expect(described_class.new(scheduled_message: agendada).perform).to be_nil

        expect(agendada.reload).to be_cancelled
        expect(agendada.error_message).to eq(I18n.t('scheduled_messages.errors.discarded_by_assistant_review'))
      end

      it 'com humano atribuído, sai como foi escrita, sem revisão' do
        conversation.update!(assignee: human)

        message = described_class.new(scheduled_message: agendada).perform

        expect(Captain::Conversation::ResponseBuilderJob).not_to have_received(:perform_now)
        expect(message.content).to eq('Texto pronto')
      end

      it 'com handoff esperando humano, sai como foi escrita, sem revisão' do
        conversation.update!(custom_attributes: { 'aguardando_humano_desde' => 30.minutes.ago.iso8601 })

        described_class.new(scheduled_message: agendada).perform

        expect(Captain::Conversation::ResponseBuilderJob).not_to have_received(:perform_now)
        expect(agendada.reload).to be_sent
      end
    end
  end

  # CHAT-213: a trava de teste (only_contact_phones) vale para a agendada que a IA escreveu antes
  # de a trava ser ligada. A de pessoa não passa pela trava: ela é do assistente.
  describe 'trava de teste do assistente' do
    before do
      cliente_falou(2.hours)
      contact.update!(phone_number: '+5565999111222')
    end

    def travar(telefone)
      assistant.update!(behavior: { 'router' => { 'only_contact_phones' => [telefone] } })
    end

    it 'descarta a agendada da IA para contato fora da trava, sem enviar nada' do
      travar('+5511888887777')
      scheduled = agendada_da_ia

      expect(described_class.new(scheduled_message: scheduled).perform).to be_nil
      expect(scheduled.reload).to be_cancelled
      expect(scheduled.error_message).to eq(I18n.t('scheduled_messages.errors.contact_outside_test_lock'))
      expect(conversation.messages.outgoing.count).to eq(0)
    end

    it 'envia a agendada da IA para contato na trava, como antes' do
      travar('556599111222')
      scheduled = agendada_da_ia

      message = described_class.new(scheduled_message: scheduled).perform

      expect(message.sender).to eq(assistant)
      expect(scheduled.reload).to be_sent
    end

    it 'não barra a agendada criada por pessoa' do
      travar('+5511888887777')
      scheduled = ScheduledMessage.create!(conversation: conversation, inbox: inbox, message: 'Oi',
                                           scheduled_at: 1.minute.from_now, status: :pending, scheduled_by: human)

      expect(described_class.new(scheduled_message: scheduled).perform.sender).to eq(human)
      expect(scheduled.reload).to be_sent
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
