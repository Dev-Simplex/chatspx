require 'rails_helper'

# Todos os textos abaixo são mensagens REAIS de clientes (conta 6), colhidas na medição de
# 01/09/2026 sobre 7.145 mensagens. O critério anterior — match exato da mensagem inteira —
# capturava ZERO delas.
RSpec.describe Contacts::OptOutDetector do
  describe '.opt_out?' do
    context 'when the whole message is the keyword' do
      it 'recognises the formal opt-out the template footer asks for' do
        ['PARAR', 'parar', 'Parar.', 'SAIR', 'stop.', 'Cancelar'].each do |texto|
          expect(described_class).to be_opt_out(texto), "esperava opt-out em #{texto.inspect}"
        end
      end

      # A razão de o match ser exato, e não substring: a palavra aparece no meio de frases
      # que dizem o oposto.
      it 'does not trip on the keyword buried in a sentence that means the opposite' do
        expect(described_class).not_to be_opt_out('não vou parar de procurar')
        expect(described_class).not_to be_opt_out('pode parar na frente do prédio?')
      end
    end

    # É esta a classe que ninguém capturava: o cliente recusa com educação, sem usar a
    # palavra-gatilho.
    context 'when the refusal is what the message is about' do
      [
        'Não tenho interesse',
        'Não tenho interesse.',
        'No momento não tenho interesse',
        'Não tenho interesse no momento, mas obrigada!',
        'Boa tarde, não tenho interesse, obrigada.',
        'Bom dia. Agradeço. Não tenho interesse.',
        'Agradeço ,más não tenho interesse no momento.',
        'Oi Lucas, não tenho interesse. Obrigado',
        'Por inquanto não tenho interesse',
        'No momento não tenho interesse. Obrigada pela lembrança',
        'Não quero mais receber',
        'Para de mandar mensagem',
        'me tira dessa lista'
      ].each do |texto|
        it "treats #{texto.inspect} as opt-out" do
          expect(described_class).to be_opt_out(texto)
        end
      end
    end

    # O contraponto, e o motivo de o critério não poder ser substring nem comprimento: nestas
    # o cliente recusa UMA coisa e pede outra. Suprimir aqui calaria um lead ativo.
    context 'when the refusal comes with a request attached' do
      [
        'Nao tenho interesse em compra no momento. Gostaria de algumas opções de casa para locação',
        'não tenho interesse no momento não. Inclusive eu to com um terreno pra colocar a venda',
        'Não tenho interesse, quero vender meu terreno lá',
        'Olá, não tenho interesse em novos imóveis. O interesse é saber se há atualização do recibo',
        'Não tenho interesse que vocês continuem administração dessa kitnet'
      ].each do |texto|
        it "keeps #{texto[0, 45].inspect}... receiving" do
          expect(described_class).not_to be_opt_out(texto)
        end
      end
    end

    context 'when there is nothing to decide' do
      it 'says no for blank and for ordinary conversation' do
        ['', '   ', nil, 'Bom dia! Queria ver uma casa de 2 quartos', 'Quanto custa?'].each do |texto|
          expect(described_class).not_to be_opt_out(texto)
        end
      end
    end
  end
end
