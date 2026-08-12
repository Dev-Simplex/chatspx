require 'rails_helper'

RSpec.describe NpsSurveys::ReopenGuard do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :resolved) }

  def create_active_nps(sent_at: 1.hour.ago, message_id: nil)
    create(:nps_response, conversation: conversation, status: :sent, answered_at: nil, score: nil,
                          sent_at: sent_at, metadata: message_id ? { 'message_id' => message_id } : {})
  end

  # build (e nao create) de proposito: o guard roda no after_create_commit da Message, entao
  # criar a mensagem ja consumiria a decisao e mudaria o status da conversa antes da assercao.
  def guard_for(content, created_at: 1.minute.ago)
    message = build(:message, account: account, inbox: inbox, conversation: conversation,
                              message_type: :incoming, content: content, created_at: created_at)
    described_class.new(message: message)
  end

  describe '#prevent_reopen? with an active survey' do
    before { create_active_nps }

    context 'when the LLM will decide (LlmGate)' do
      it 'holds the reopen for a compliment without a digit when sentiment is enabled (regressao do bug)' do
        inbox.update!(nps_config: { 'sentiment_detractor_enabled' => true })
        expect(guard_for('excelente').prevent_reopen?).to be(true)
      end

      it 'holds the reopen for a written-out score when gpt_parse is enabled' do
        inbox.update!(nps_config: { 'gpt_parse_enabled' => true })
        expect(guard_for('nota nove').prevent_reopen?).to be(true)
      end

      it 'does not hold a compliment when both toggles are off (sem LLM nao ha quem decida)' do
        inbox.update!(nps_config: { 'sentiment_detractor_enabled' => false, 'gpt_parse_enabled' => false })
        expect(guard_for('excelente').prevent_reopen?).to be(false)
      end

      it 'does not hold a long message even with sentiment enabled (fora da candidatura do LLM)' do
        inbox.update!(nps_config: { 'sentiment_detractor_enabled' => true })
        expect(guard_for("#{'a' * 281} excelente").prevent_reopen?).to be(false)
      end
    end

    context 'when the regex already decides' do
      it 'holds the reopen for a valid score' do
        expect(guard_for('9').prevent_reopen?).to be(true)
      end

      it 'holds the reopen for an out-of-range score' do
        expect(guard_for('11').prevent_reopen?).to be(true)
      end

      it 'holds the reopen for an obvious failed attempt' do
        expect(guard_for('abc').prevent_reopen?).to be(true)
      end

      it 'holds the reopen for a widget submission' do
        message = build(:message, account: account, inbox: inbox, conversation: conversation,
                                  message_type: :incoming, content: 'nps',
                                  content_attributes: { submitted_values: { nps_response: { score: 8 } } })
        expect(described_class.new(message: message).prevent_reopen?).to be(true)
      end
    end

    it 'does not hold an outgoing message' do
      message = build(:message, account: account, inbox: inbox, conversation: conversation,
                                message_type: :outgoing, content: '9')
      expect(described_class.new(message: message).prevent_reopen?).to be(false)
    end

    it 'does not hold when the conversation is not resolved' do
      conversation.update!(status: :open)
      expect(guard_for('9').prevent_reopen?).to be(false)
    end
  end

  describe '#prevent_reopen? without a decidable survey' do
    it 'does not hold when there is no active survey' do
      inbox.update!(nps_config: { 'sentiment_detractor_enabled' => true })
      expect(guard_for('excelente').prevent_reopen?).to be(false)
    end

    it 'does not hold when the survey was already answered' do
      inbox.update!(nps_config: { 'sentiment_detractor_enabled' => true })
      create(:nps_response, conversation: conversation, status: :responded, score: 9, answered_at: Time.current)
      expect(guard_for('excelente').prevent_reopen?).to be(false)
    end

    it 'does not hold when the survey expired (expiration_hours)' do
      inbox.update!(nps_config: { 'sentiment_detractor_enabled' => true, 'expiration_hours' => 24 })
      create_active_nps(sent_at: 25.hours.ago)
      expect(guard_for('excelente').prevent_reopen?).to be(false)
    end

    it 'does not hold when the message is older than the survey' do
      create_active_nps(sent_at: 1.hour.ago)
      expect(guard_for('9', created_at: 2.hours.ago).prevent_reopen?).to be(false)
    end

    # Caminho REAL do agente-assumiu: o NpsSurveyListener dismissa a pesquisa quando um agente
    # envia mensagem (dismiss_active_nps), entao nao sobra pesquisa ativa para o guard segurar.
    it 'does not hold when the survey was dismissed (agente assumiu a conversa)' do
      inbox.update!(nps_config: { 'sentiment_detractor_enabled' => true })
      create(:nps_response, conversation: conversation, status: :dismissed, score: nil, answered_at: nil)
      expect(guard_for('excelente').prevent_reopen?).to be(false)
    end

    # Contrato documentado no cabecalho do guard ("agent replied after -> nao segura"). Ficou pinado
    # como pending enquanto o #agent_responded_after_nps? usava `content_attributes ->> 'nps_survey'`:
    # content_attributes e JSON serializado como STRING, entao `->>` devolvia NULL, `NOT (NULL =
    # 'true')` era NULL (nao TRUE) e a linha era descartada — o predicado nunca casava. Corrigido nos
    # DOIS lados de uma vez (guard e ResponseBuilder usam a mesma query; consertar so um recriaria a
    # divergencia). Ver Message::CONTENT_ATTRIBUTES_JSON.
    it 'does not hold when an agent replied after the survey was sent' do
      nps_message = create(:message, account: account, inbox: inbox, conversation: conversation,
                                     message_type: :outgoing, content: 'De 0 a 10, quanto voce nos recomenda?',
                                     content_attributes: { nps_survey: true })
      create_active_nps(message_id: nps_message.id)
      create(:message, account: account, inbox: inbox, conversation: conversation, sender: agent,
                       message_type: :outgoing, content: 'Oi, posso ajudar em algo mais?')

      expect(guard_for('9').prevent_reopen?).to be(false)
    end
  end
end
