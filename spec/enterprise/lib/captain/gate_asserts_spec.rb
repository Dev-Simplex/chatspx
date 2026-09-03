require 'rails_helper'

# 6.01 — as REGRAS, isoladas do banco. Aqui não há conversa, episódio nem tool call:
# só texto entrando e veredito saindo. É o que garante que o gate pós-fato e o
# guardrail de pré-envio julguem pela MESMA régua.
RSpec.describe Captain::GateAsserts do
  describe '.tool_result_useful?' do
    it 'is true when the tool returned content' do
      expect(described_class.tool_result_useful?(status: 'ok', result_preview: '3 imoveis: A, B, C')).to be(true)
    end

    it 'is false when the tool errored, even with a preview' do
      expect(described_class.tool_result_useful?(status: 'error', result_preview: 'A, B')).to be(false)
    end

    it 'is false when the preview is blank' do
      expect(described_class.tool_result_useful?(status: 'ok', result_preview: '   ')).to be(false)
      expect(described_class.tool_result_useful?(status: 'ok', result_preview: nil)).to be(false)
    end

    # Negar depois de um retorno que JÁ era vazio não é contradição — é a IA
    # repassando o vazio, que é o comportamento correto.
    it 'is false when the preview itself says nothing was found' do
      ['nenhum resultado', 'não encontrei nada', 'not found', '[]'].each do |empty|
        expect(described_class.tool_result_useful?(status: 'ok', result_preview: empty)).to be(false)
      end
    end
  end

  describe '.negative_reply?' do
    it 'catches the four denial forms the regex declares' do
      ['Não encontrei imóveis com esse perfil.', 'nao achei nada por aqui', 'Não localizei o pedido',
       'Não temos esse modelo'].each do |text|
        expect(described_class.negative_reply?(text)).to be(true)
      end
    end

    it 'does not fire on an affirmative answer' do
      expect(described_class.negative_reply?('Encontrei 3 imóveis: A, B e C.')).to be(false)
    end

    it 'does not fire on a denial about something else than a lookup' do
      expect(described_class.negative_reply?('Não posso responder isso.')).to be(false)
    end
  end

  describe '.contradicts_tool?' do
    it 'is true when a useful tool result is denied' do
      expect(
        described_class.contradicts_tool?('Não encontrei imóveis assim.', status: 'ok', result_preview: 'A, B, C')
      ).to be(true)
    end

    it 'is false when the answer does not deny' do
      expect(
        described_class.contradicts_tool?('Encontrei 3 opções.', status: 'ok', result_preview: 'A, B, C')
      ).to be(false)
    end

    it 'is false when the tool had nothing to contradict' do
      expect(
        described_class.contradicts_tool?('Não encontrei imóveis assim.', status: 'ok', result_preview: 'nenhum')
      ).to be(false)
    end
  end

  describe '.repetition_key' do
    let(:long_text) { 'Claro! Posso te ajudar com isso agora mesmo, é só me dizer o bairro.' }

    it 'normalizes case and whitespace so the same text collides' do
      expect(described_class.repetition_key(long_text))
        .to eq(described_class.repetition_key("  CLARO! Posso te ajudar   com isso agora mesmo,\né só me dizer o bairro.  "))
    end

    it 'returns nil below the minimum length, because short repetition is not a loop' do
      expect(long_text.length).to be > described_class::MIN_REPEAT_LENGTH
      expect(described_class.repetition_key('Claro!')).to be_nil
      expect(described_class.repetition_key('a' * (described_class::MIN_REPEAT_LENGTH - 1))).to be_nil
      expect(described_class.repetition_key('a' * described_class::MIN_REPEAT_LENGTH)).not_to be_nil
    end
  end

  describe '.finding' do
    it 'builds the exact shape that response_findings stores' do
      finding = described_class.finding(categoria: 'contradisse_tool', porque: 'porque sim', trecho: 'x' * 200)

      expect(finding).to include('origem' => 'gate', 'quem' => 'ia', 'categoria' => 'contradisse_tool',
                                 'severidade' => 'alta', 'message_id' => nil, 'porque' => 'porque sim')
      expect(finding['trecho'].length).to eq(120)
    end

    it 'accepts a lower severity without changing the shape' do
      finding = described_class.finding(categoria: 'ignorou_erro_da_tool', porque: 'x', severidade: 'media')

      expect(finding['severidade']).to eq('media')
      expect(finding.keys).to contain_exactly('origem', 'quem', 'categoria', 'severidade', 'message_id', 'trecho', 'porque')
    end
  end
end
