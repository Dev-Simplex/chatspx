require 'rails_helper'

RSpec.describe Captain::Conversation::FollowupJob, type: :job do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:token) { 'followup-token-1' }
  let(:conversation) do
    create(:conversation, inbox: inbox, account: account, status: :open,
                          assignee_agent_bot: assistant.mirror_agent_bot,
                          custom_attributes: { 'followup_token' => token, 'followup_count' => 1 })
  end

  before do
    allow(Captain::Conversation::ResponseBuilderJob).to receive(:perform_now)
    # Última mensagem visível é da IA (lead sem responder) — pré-condição da cutucada.
    create(:message, conversation: conversation, account: account, inbox: inbox,
                     message_type: :outgoing, sender: assistant, content: 'Posso ajudar em algo mais?')
    # 11h em America/Cuiaba — fora das quiet hours (não remarca).
    travel_to Time.utc(2026, 6, 11, 15, 0)
  end

  # ARMADILHA: o travel_to acima roda DEPOIS da outgoing, então tudo criado dentro dos exemplos
  # nasce com created_at ANTERIOR a ela e `order(:created_at).last` devolve a mensagem da IA.
  # Quem precisa que a última mensagem seja do cliente tem que carimbar a data explicitamente.
  def responde_por_ultimo(texto)
    create(:message, conversation: conversation, account: account, inbox: inbox,
                     message_type: :incoming, content: texto,
                     created_at: conversation.messages.maximum(:created_at) + 1.second)
  end

  context 'when the conversation is still owned by the assistant mirror' do
    it 'fires the nudge from the owner assistant and consumes token/followup_count' do
      described_class.perform_now(conversation, token)

      expect(Captain::Conversation::ResponseBuilderJob)
        .to have_received(:perform_now).with(conversation, assistant, directive: a_string_including('cutucada'))
      expect(conversation.reload.custom_attributes['followup_count']).to eq(2)
      expect(conversation.reload.custom_attributes['followup_token']).to be_nil
    end

    it 'no longer blocks on the atendimento_humano custom attribute (trava morta)' do
      conversation.update!(custom_attributes: conversation.custom_attributes.merge('atendimento_humano' => true))

      described_class.perform_now(conversation, token)

      expect(Captain::Conversation::ResponseBuilderJob).to have_received(:perform_now)
    end
  end

  context 'when the conversation was transferred to another assistant (IA→IA)' do
    it 'fires the nudge from the CURRENT owner, not the one that scheduled it' do
      other_assistant = create(:captain_assistant, account: account)
      conversation.update!(assignee_agent_bot: other_assistant.mirror_agent_bot)

      described_class.perform_now(conversation, token)

      expect(Captain::Conversation::ResponseBuilderJob)
        .to have_received(:perform_now).with(conversation, other_assistant, directive: kind_of(String))
    end
  end

  # A3 (nit 9): dono resolvido ANTES de consumir token/followup_count — cutucada que não
  # vai sair não gasta tentativa nem invalida o token.
  context 'when a human owns the conversation' do
    before do
      conversation.update!(assignee: agent)
    end

    it 'dies without firing and without consuming token or followup_count' do
      described_class.perform_now(conversation, token)

      expect(Captain::Conversation::ResponseBuilderJob).not_to have_received(:perform_now)
      expect(conversation.reload.custom_attributes['followup_count']).to eq(1)
      expect(conversation.reload.custom_attributes['followup_token']).to eq(token)
    end

    it 'does not move the card to Frio even with followups exhausted' do
      allow(Spx::Tozi::FunnelPlacementService).to receive(:move)
      conversation.update!(custom_attributes: conversation.custom_attributes.merge('followup_count' => described_class::MAX_FOLLOWUPS))

      described_class.perform_now(conversation, token)

      expect(Spx::Tozi::FunnelPlacementService).not_to have_received(:move)
      expect(conversation.reload.custom_attributes['followup_token']).to eq(token)
    end
  end

  context 'when the conversation has no owner' do
    it 'dies without firing and without consuming the token' do
      conversation.update!(assignee_agent_bot: nil)

      described_class.perform_now(conversation, token)

      expect(Captain::Conversation::ResponseBuilderJob).not_to have_received(:perform_now)
      expect(conversation.reload.custom_attributes['followup_token']).to eq(token)
    end
  end

  context 'when followups are exhausted and the AI still owns the conversation' do
    it 'cools the lead, moves the card to Frio and hands off to a human' do
      allow(Spx::Tozi::FunnelPlacementService).to receive(:move)
      handoff = instance_double(Captain::Conversation::HumanHandoffService, perform: true)
      allow(Captain::Conversation::HumanHandoffService).to receive(:new).and_return(handoff)
      conversation.update!(custom_attributes: conversation.custom_attributes.merge('followup_count' => described_class::MAX_FOLLOWUPS))

      described_class.perform_now(conversation, token)

      expect(conversation.reload.custom_attributes['tozi_status_lead']).to eq('esfriado')
      expect(Spx::Tozi::FunnelPlacementService).to have_received(:move).with(conversation: conversation, to: 'frio')
      expect(Captain::Conversation::HumanHandoffService).to have_received(:new)
      expect(handoff).to have_received(:perform)
      expect(Captain::Conversation::ResponseBuilderJob).not_to have_received(:perform_now)
    end
  end

  context 'when the token is stale (replaced by a newer followup)' do
    it 'does nothing' do
      described_class.perform_now(conversation, 'another-token')

      expect(Captain::Conversation::ResponseBuilderJob).not_to have_received(:perform_now)
      expect(conversation.reload.custom_attributes['followup_count']).to eq(1)
    end
  end

  # Regressao (conv 20320): a cutucada existia pra cumprir um COMPROMISSO — o cliente ficou de
  # confirmar algo num horario combinado. Ele fechou a conversa socialmente ("obrigada, boa
  # noite") e isso matava a cutucada em duas camadas: lead_replied? cancelava so por a ultima
  # mensagem ser dele, e a directive mandava o modelo responder [IGNORAR] porque ele "encerrou
  # ou agradeceu". Despedida educada nao desmarca o que ficou combinado.
  context 'when a commitment is pending and the lead only closed socially' do
    let(:motivo) { 'cliente ia confirmar com o marido e responder ate as 19h' }

    before do
      conversation.update!(custom_attributes: conversation.custom_attributes.merge('followup_motivo' => motivo))
      responde_por_ultimo('Obrigada, boa noite!')
    end

    it 'still fires the nudge' do
      described_class.perform_now(conversation, token)

      expect(Captain::Conversation::ResponseBuilderJob).to have_received(:perform_now)
    end

    it 'carries the commitment and drops the order to ignore a social close' do
      captured = nil
      allow(Captain::Conversation::ResponseBuilderJob).to receive(:perform_now) { |_c, _a, directive:| captured = directive }

      described_class.perform_now(conversation, token)

      expect(captured).to include(motivo)
      expect(captured).not_to include('agradeceu')
    end

    it 'consumes the commitment so it does not leak into later preventive nudges' do
      described_class.perform_now(conversation, token)

      expect(conversation.reload.custom_attributes['followup_motivo']).to be_blank
    end
  end

  # Controle: sem compromisso, a cutucada e so preventiva — resposta do cliente cancela mesmo.
  context 'when there is no commitment and the lead replied' do
    it 'still cancels the preventive nudge' do
      responde_por_ultimo('Oi, me manda mais fotos?')

      described_class.perform_now(conversation, token)

      expect(Captain::Conversation::ResponseBuilderJob).not_to have_received(:perform_now)
      expect(conversation.reload.custom_attributes['followup_token']).to eq(token)
    end
  end

  # BORDA DA JANELA (contrato do eixo, regra 1). Cutucada e engrenagem in-window; fora da janela
  # quem bate na porta e a repescagem — template pago, escolhido pelo operador — que ainda nao
  # existe. Texto livre fora da janela nao vira repescagem disfarcada: vira envio recusado.
  context 'when the messaging window has already closed' do
    let(:inbox) { create(:channel_api, account: account, additional_attributes: { agent_reply_time_window: '24' }).inbox }

    before do
      # A ancora da janela e a ultima mensagem do CLIENTE (regra 3), nao a da IA: 25h -> fechada.
      create(:message, conversation: conversation, account: account, inbox: inbox,
                       message_type: :incoming, content: 'Vou pensar e te falo', created_at: 25.hours.ago)
    end

    it 'dies without firing and without consuming token or followup_count' do
      described_class.perform_now(conversation, token)

      expect(Captain::Conversation::ResponseBuilderJob).not_to have_received(:perform_now)
      expect(conversation.reload.custom_attributes['followup_count']).to eq(1)
      expect(conversation.reload.custom_attributes['followup_token']).to eq(token)
    end

    # Morte definitiva, nao adiamento: a manha das quiet hours chega sozinha, a janela nao — so a
    # resposta do cliente reabre, e a cutucada e justamente o que nao pode causar esse evento.
    it 'does not reschedule itself for whenever the window might reopen' do
      expect { described_class.perform_now(conversation, token) }.not_to have_enqueued_job(described_class)
    end

    # A borda vem ANTES do cool_down porque o HumanHandoffService termina no OutOfOffice, que cria
    # mensagem sem checar can_reply? — seria exatamente o "outro caminho de envio" que a regra 1 veta.
    it 'does not escalate to a human either, even with the followups exhausted' do
      allow(Spx::Tozi::FunnelPlacementService).to receive(:move)
      allow(Captain::Conversation::HumanHandoffService).to receive(:new)
      conversation.update!(custom_attributes: conversation.custom_attributes.merge('followup_count' => described_class::MAX_FOLLOWUPS))

      described_class.perform_now(conversation, token)

      expect(Captain::Conversation::HumanHandoffService).not_to have_received(:new)
      expect(Spx::Tozi::FunnelPlacementService).not_to have_received(:move)
    end

    # Compromisso tambem nao atravessa: fora da janela ele muda de FORMA (vira template), e essa
    # forma nao existe ainda. O motivo fica armado pra quando existir, em vez de ser consumido.
    it 'holds the border even with a pending commitment, keeping the commitment armed' do
      conversation.update!(custom_attributes: conversation.custom_attributes.merge('followup_motivo' => 'ia confirmar com o marido'))

      described_class.perform_now(conversation, token)

      expect(Captain::Conversation::ResponseBuilderJob).not_to have_received(:perform_now)
      expect(conversation.reload.custom_attributes['followup_motivo']).to be_present
    end
  end

  context 'when the messaging window is still open' do
    let(:inbox) { create(:channel_api, account: account, additional_attributes: { agent_reply_time_window: '24' }).inbox }

    it 'fires the nudge normally' do
      create(:message, conversation: conversation, account: account, inbox: inbox,
                       message_type: :incoming, content: 'Manda os detalhes', created_at: 2.hours.ago)

      described_class.perform_now(conversation, token)

      expect(Captain::Conversation::ResponseBuilderJob).to have_received(:perform_now)
    end
  end

  # Armadilha do can_reply?: ele devolve TRUE quando o canal nao tem janela configurada. E de
  # proposito — a guarda nao pode calar a cutucada em canal que nao tem janela nenhuma.
  context 'when the channel has no messaging window at all' do
    it 'fires the nudge even without any incoming message to anchor a window' do
      expect(conversation.messages.incoming).to be_empty

      described_class.perform_now(conversation, token)

      expect(Captain::Conversation::ResponseBuilderJob).to have_received(:perform_now)
    end
  end
end
