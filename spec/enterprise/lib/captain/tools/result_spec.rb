require 'rails_helper'

RSpec.describe Captain::Tools::Result do
  describe 'estados' do
    it 'só aceita os estados declarados' do
      expect { described_class.new(status: :meio_certo, texto: 'x') }.to raise_error(ArgumentError)
    end

    # O vocabulário da coluna `captain_tool_calls.status` é anterior a esta classe: 'ok' e
    # 'error' já estão gravados no banco e o eval lê de lá. Trocá-los invalidaria trace antigo.
    it 'preserva o vocabulário já gravado no banco para sucesso e erro' do
      expect(described_class.sucesso('x').status_persistido).to eq('ok')
      expect(described_class.erro('x').status_persistido).to eq('error')
    end

    it 'separa ausência CONFIRMADA de tudo o mais — é o único estado que autoriza dizer "não temos"' do
      expect(described_class.vazio_completo('nada no critério').ausencia_confirmada?).to be true
      expect(described_class.desconhecido('não deu pra saber').ausencia_confirmada?).to be false
      expect(described_class.erro('caiu').ausencia_confirmada?).to be false
      expect(described_class.parcial('parte').ausencia_confirmada?).to be false
    end

    it 'classifica vazio_completo e parcial como consulta que chegou a uma resposta' do
      expect(described_class::CONFIRMADOS).to include('ok', 'vazio_completo', 'parcial')
      expect(described_class::NAO_CONFIRMADOS).to include('error', 'desconhecido')
      expect(described_class::CONFIRMADOS & described_class::NAO_CONFIRMADOS).to be_empty
    end
  end

  # O contrato com a gem `agents` não muda: quem consome `perform` continua recebendo String.
  describe 'fronteira com a gem' do
    it 'atravessa como o texto que o modelo lê' do
      expect(described_class.sucesso('Casa no Centro').to_s).to eq('Casa no Centro')
    end

    # O detalhe técnico existe pro log e pro trace, e é justamente o que NÃO pode virar fala.
    it 'mantém o detalhe técnico fora do texto' do
      resultado = described_class.erro('Não consegui consultar agora.', detalhe: 'HTTP 503')

      expect(resultado.to_s).not_to include('503')
      expect(resultado.detalhe).to eq('HTTP 503')
    end

    it 'reconhece o que ainda não é tipado, para migrar uma ferramenta por vez' do
      expect(described_class.tipado?('string crua')).to be false
      expect(described_class.tipado?(described_class.sucesso('x'))).to be true
    end
  end
end
