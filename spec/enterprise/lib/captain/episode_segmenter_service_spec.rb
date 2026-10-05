require 'rails_helper'

RSpec.describe Captain::EpisodeSegmenterService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  describe '#perform' do
    it 'segments the conversation messages into an open episode' do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing)

      expect { described_class.new(conversation: conversation).perform }
        .to change(Captain::ConversationEpisode.where(conversation_id: conversation.id), :count).by(1)

      episode = Captain::ConversationEpisode.find_by(conversation_id: conversation.id)
      expect(episode.boundary_reason).to eq('aberto')
      expect(episode.ended_at).to be_nil
      expect(episode.mensagens).to eq(2)
    end

    # GlitchTip #128: episódio órfão (conversa apagada — a tabela não tem FK nem dependent:)
    # entrega conversation: nil e estourava em #rows, matando o eval da conta inteira.
    context 'when the conversation is nil (orphan episode)' do
      it 'returns an empty list instead of raising' do
        expect { described_class.new(conversation: nil).perform }.not_to raise_error
        expect(described_class.new(conversation: nil).perform).to eq([])
      end

      it 'does not create any episode' do
        expect { described_class.new(conversation: nil).perform }
          .not_to change(Captain::ConversationEpisode, :count)
      end
    end
  end

  # CHAT-180 (conv 22777, conta 6): o segmentador comparava o enum com 2 e 3, mas o `pluck`
  # devolve o rótulo. A resolução e o HSM não cortavam nada, e o atendimento resolvido de
  # véspera chegava inteiro à IA que assumiu a reentrada 22h depois (abaixo do gap de 24h).
  describe '#preview' do
    # Perto de agora: o último episódio só fica 'aberto' se o gap ainda não venceu.
    let(:inicio) { 23.hours.ago }

    def mensagem(tipo, instante, conteudo = 'oi', **attrs)
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: tipo, content: conteudo, created_at: instante, **attrs)
    end

    it 'abre episódio novo quando o cliente volta depois de uma resolução, mesmo abaixo do gap' do
      mensagem(:outgoing, inicio)
      mensagem(:incoming, inicio + 1.minute)
      mensagem(:activity, inicio + 18.hours, 'Conversa marcada como resolvida por um atendente')
      reentrada = mensagem(:incoming, inicio + 22.hours)

      segmentos = described_class.new(conversation: conversation).preview

      expect(segmentos.map(&:reason)).to eq(%w[resolve aberto])
      expect(segmentos.last.first_id).to eq(reentrada.id)
    end

    it 'não abre episódio numa activity' do
      mensagem(:incoming, inicio)
      mensagem(:activity, inicio + 1.minute, 'O sistema reabriu a conversa')

      segmentos = described_class.new(conversation: conversation).preview

      expect(segmentos.size).to eq(1)
      expect(segmentos.first.count).to eq(1)
    end

    it 'abre episódio novo num template de saída' do
      mensagem(:incoming, inicio)
      template = mensagem(:template, inicio + 2.hours)

      segmentos = described_class.new(conversation: conversation).preview

      expect(segmentos.map(&:reason)).to eq(%w[hsm_campanha aberto])
      expect(segmentos.last.first_id).to eq(template.id)
    end

    # Decisão do Paulo (01/10/2026): o cron do Eval NÃO muda. A mesma conversa, gravada pelo
    # #perform, continua num episódio só, como era antes da correção do runtime.
    it 'keeps the Eval segmentation unchanged in #perform' do
      mensagem(:outgoing, inicio)
      mensagem(:incoming, inicio + 1.minute)
      mensagem(:activity, inicio + 18.hours, 'Conversa marcada como resolvida por um atendente')
      mensagem(:incoming, inicio + 22.hours)
      mensagem(:template, inicio + 22.hours + 5.minutes)

      described_class.new(conversation: conversation).perform

      episodios = Captain::ConversationEpisode.where(conversation_id: conversation.id)
      expect(episodios.pluck(:boundary_reason, :mensagens)).to eq([['aberto', 5]])
    end
  end
end
