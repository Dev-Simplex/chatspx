require 'rails_helper'

# O que a conversa de destino recebe da origem na troca de canal: quem atende lá não começa do zero.
RSpec.describe Whatsapp::TrocaDeCanalResumo do
  let(:account) { create(:account) }
  let(:caixa) { create(:inbox, account: account, name: 'Campanhas') }
  let(:bot) { create(:agent_bot, account: account, name: 'Assistente') }
  let(:origem) do
    create(:conversation, account: account, inbox: caixa, assignee_agent_bot: bot,
                          custom_attributes: { 'resumo_atendimento_ia' => 'Cliente quer alugar um apartamento.' })
  end
  let(:passagem) { described_class.new(origem: origem, motivo: 'Você quer falar sobre locação.') }

  it 'monta a nota com a origem, o motivo, o resumo da IA e quem atendia' do
    esperado = ["Cliente veio da conversa ##{origem.display_id}, na caixa Campanhas (chat do site). Motivo: Você quer falar sobre locação.",
                "Resumo da origem:
Cliente quer alugar um apartamento.",
                'Quem atendia na origem: Assistente (IA)'].join("

")
    expect(passagem.nota).to eq(esperado)
  end

  it 'monta o atributo que a IA do destino lê' do
    expect(passagem.atributo).to end_with('Motivo: Você quer falar sobre locação. Resumo: Cliente quer alugar um apartamento.')
  end

  it 'sem resumo nenhum, leva só a origem e o motivo' do
    origem.update!(custom_attributes: {})

    expect(passagem.atributo).to end_with('Motivo: Você quer falar sobre locação.')
    expect(passagem.nota).not_to include('Resumo')
  end

  context 'when the journey generator exists' do
    let(:gerador) { Class.new { def self.for(_conversa) = 'Pedido, jornada, quem atendeu e pendências.' } }

    before { stub_const('Captain::Conversation::JourneySummary', gerador) }

    it 'usa o texto do gerador no lugar do resumo da IA, sem repetir quem atendia' do
      expect(passagem.nota).to include("Resumo da origem:
Pedido, jornada, quem atendeu e pendências.")
      expect(passagem.nota).not_to include('Quem atendia')
    end

    it 'cai no resumo da IA quando o gerador devolve nil' do
      allow(gerador).to receive(:for).and_return(nil)

      expect(passagem.nota).to include('Cliente quer alugar um apartamento.')
    end
  end
end
