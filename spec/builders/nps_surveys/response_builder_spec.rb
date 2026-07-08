require 'rails_helper'

RSpec.describe NpsSurveys::ResponseBuilder do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :resolved) }

  def create_active_nps(sent_at: 1.hour.ago)
    create(:nps_response, conversation: conversation, status: :sent, answered_at: nil, score: nil, sent_at: sent_at)
  end

  def incoming(content)
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :incoming, content: content)
  end

  def perform_for(content)
    described_class.new(message: incoming(content)).perform
  end

  describe 'per-band thank-you' do
    before do
      inbox.update!(nps_config: { 'thank_you_promoter' => 'Que bom!', 'thank_you_detractor' => 'Vamos melhorar',
                                  'thank_you_message' => 'Obrigado' })
      create_active_nps
    end

    it 'sends the promoter message for 9-10' do
      perform_for('10')
      expect(conversation.messages.where(message_type: :outgoing).last.content).to eq('Que bom!')
    end

    it 'sends the detractor message for 0-6' do
      perform_for('3')
      expect(conversation.messages.where(message_type: :outgoing).where(content: 'Vamos melhorar')).to exist
    end

    it 'falls back to the generic message for a passive when no band message is set' do
      perform_for('7')
      expect(conversation.messages.where(message_type: :outgoing).last.content).to eq('Obrigado')
    end
  end

  describe 'detractor routing (0-6)' do
    before do
      inbox.update!(nps_config: {
                      'detractor_reopen' => true,
                      'detractor_label' => 'detrator',
                      'detractor_assignee_id' => agent.id
                    })
      create_active_nps
    end

    it 'reopens, assigns and labels a detractor conversation' do
      perform_for('2')
      conversation.reload
      expect(conversation.status).to eq('open')
      expect(conversation.assignee_id).to eq(agent.id)
      expect(conversation.label_list).to include('detrator')
    end

    it 'stamps detractor_routed_at on the nps response' do
      perform_for('2')
      nps = conversation.nps_responses.order(created_at: :desc).first
      expect(nps.metadata['detractor_routed_at']).to be_present
    end

    it 'does not route promoters or passives' do
      perform_for('9')
      conversation.reload
      expect(conversation.status).to eq('resolved')
      expect(conversation.label_list).not_to include('detrator')
    end

    it 'does not duplicate the label when already present' do
      conversation.add_labels('detrator')
      perform_for('1')
      conversation.reload
      expect(conversation.label_list.count { |l| l == 'detrator' }).to eq(1)
    end
  end

  describe 'detractor routing when unconfigured' do
    before do
      inbox.update!(nps_config: {})
      create_active_nps
    end

    it 'leaves the conversation resolved and unlabeled' do
      perform_for('2')
      conversation.reload
      expect(conversation.status).to eq('resolved')
      expect(conversation.label_list).to be_empty
    end
  end

  describe 'GPT-parse fallback' do
    before { create_active_nps }

    it 'uses the LLM to parse a written-out score when enabled and regex fails' do
      inbox.update!(nps_config: { 'gpt_parse_enabled' => true })
      allow(NpsSurveys::ScoreLlmParser).to receive(:extract).and_return(9)
      perform_for('nota nove')
      nps = conversation.nps_responses.order(created_at: :desc).first
      expect(nps.status).to eq('responded')
      expect(nps.score).to eq(9)
    end

    it 'does not call the LLM when disabled' do
      inbox.update!(nps_config: { 'gpt_parse_enabled' => false })
      expect(NpsSurveys::ScoreLlmParser).not_to receive(:extract)
      perform_for('nota nove')
    end

    it 'does not call the LLM for long non-numeric messages even when enabled' do
      inbox.update!(nps_config: { 'gpt_parse_enabled' => true })
      expect(NpsSurveys::ScoreLlmParser).not_to receive(:extract)
      perform_for('obrigado pelo excelente atendimento de voces todos hoje de manha')
    end
  end

  describe 'invalid responses (3 strikes -> finaliza)' do
    before do
      inbox.update!(nps_config: { 'invalid_response_message' => 'Envie uma nota de 0 a 10.' })
      create_active_nps
    end

    def invalid_nudges
      conversation.messages.where(message_type: :outgoing, content: 'Envie uma nota de 0 a 10.')
    end

    it 'sends the invalid-response message on the first two invalid attempts' do
      perform_for('abc')
      perform_for('11')
      expect(invalid_nudges.count).to eq(2)
      expect(conversation.nps_responses.first.reload.status).to eq('sent')
    end

    it 'finalizes on the third invalid attempt: dismisses NPS and does not send another nudge' do
      perform_for('abc')
      perform_for('11')
      perform_for('?')
      expect(invalid_nudges.count).to eq(2)
      nps = conversation.nps_responses.first.reload
      expect(nps.status).to eq('dismissed')
      expect(nps.dismiss_reason).to eq('invalid_responses')
    end

    it 'leaves the conversation resolved (does not repeat the survey question)' do
      perform_for('abc')
      perform_for('11')
      perform_for('?')
      expect(conversation.reload.status).to eq('resolved')
      expect(conversation.messages.where("content_attributes ->> 'nps_survey' = 'true'").count).to eq(0)
    end

    it 'marks the invalid message as an NPS system message (nao dismissa a pesquisa)' do
      perform_for('abc')
      msg = invalid_nudges.last
      expect(msg.content_attributes['nps_survey_system']).to be_truthy
    end

    it 'does not count a normal (non-attempt) message as a strike' do
      perform_for('abc')
      perform_for('quero falar com um atendente por favor agora')
      perform_for('11')
      expect(conversation.nps_responses.first.reload.status).to eq('sent')
    end
  end

  describe 'classificacao por IA sem nota (sentimento + outro assunto)' do
    before do
      inbox.update!(nps_config: { 'sentiment_detractor_enabled' => true,
                                  'thank_you_detractor' => 'Vamos melhorar',
                                  'thank_you_promoter' => 'Que bom!' })
      create_active_nps
    end

    it 'trata insatisfacao (negative) como detrator e agradece' do
      allow(NpsSurveys::ScoreLlmParser).to receive(:classify).and_return('negative')
      perform_for('pessimo, nao gostei')
      nps = conversation.nps_responses.first.reload
      expect(nps.status).to eq('responded')
      expect(nps.detractor?).to be(true)
      expect(nps.metadata['sentiment_inferred']).to be(true)
      expect(conversation.messages.where(message_type: :outgoing, content: 'Vamos melhorar')).to exist
    end

    it 'trata elogio (positive) como promotor e agradece' do
      allow(NpsSurveys::ScoreLlmParser).to receive(:classify).and_return('positive')
      perform_for('adorei o atendimento')
      nps = conversation.nps_responses.first.reload
      expect(nps.status).to eq('responded')
      expect(nps.promoter?).to be(true)
      expect(nps.metadata['sentiment_inferred']).to be(true)
      expect(conversation.messages.where(message_type: :outgoing, content: 'Que bom!')).to exist
    end

    it 'trata outro assunto (other_topic) como atendimento humano: dismissa e reabre' do
      allow(NpsSurveys::ScoreLlmParser).to receive(:classify).and_return('other_topic')
      perform_for('quero falar sobre meu pedido')
      nps = conversation.nps_responses.first.reload
      expect(nps.status).to eq('dismissed')
      expect(nps.dismiss_reason).to eq('other_topic')
      expect(conversation.reload.status).to eq('open')
    end

    it 'neutral nao registra resposta (deixa reabrir para atendimento)' do
      allow(NpsSurveys::ScoreLlmParser).to receive(:classify).and_return('neutral')
      perform_for('bom dia, tudo bem?')
      expect(conversation.nps_responses.first.reload.status).to eq('sent')
    end

    it 'nao chama a IA quando o toggle esta off' do
      inbox.update!(nps_config: { 'sentiment_detractor_enabled' => false })
      expect(NpsSurveys::ScoreLlmParser).not_to receive(:classify)
      perform_for('pessimo, nao gostei')
    end

    it 'nao chama a IA para tentativa invalida obvia (heuristica barata primeiro)' do
      expect(NpsSurveys::ScoreLlmParser).not_to receive(:classify)
      perform_for('abc')
    end

    it 'registra nota explicita sem invocar a IA' do
      expect(NpsSurveys::ScoreLlmParser).not_to receive(:classify)
      perform_for('9')
      expect(conversation.nps_responses.first.reload.score).to eq(9)
    end
  end

  describe 'agradecimento idempotente (nao duplica)' do
    before do
      inbox.update!(nps_config: { 'thank_you_promoter' => 'Que ótimo!' })
      create_active_nps
    end

    it 'nao envia o mesmo agradecimento duas vezes para a mesma resposta' do
      described_class.new(message: incoming('9')).perform
      # segunda passagem simulando reprocessamento (corrida de eventos)
      nps = conversation.nps_responses.first
      builder = described_class.new(message: incoming('comentario extra'))
      builder.send(:send_thank_you_message, nps) if builder.send(:should_send_thank_you?, nps)
      expect(conversation.messages.where(message_type: :outgoing, content: 'Que ótimo!').count).to eq(1)
    end
  end
end
