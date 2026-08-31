require 'rails_helper'

# O juiz recebia a transcrição e as tool calls, e NADA do contexto de origem — enquanto o
# agente avaliado recebe `meta_anuncio` e afins no próprio state. Resultado medido numa conta
# em 31/08/2026: a IA repetia o texto do criativo ("a partir de R$ 500/mês") e o juiz marcava
# `alucinacao` de severidade alta. Eram 61 dos 275 findings de alucinação em 30 dias.
RSpec.describe Captain::ConversationEvalService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:service) { described_class.new(conversation: conversation) }

  describe '#origem_context' do
    it 'is absent when the conversation carries no origin at all' do
      expect(service.send(:origem_context)).to be_nil
    end

    it 'carries the ad copy the agent also received' do
      conversation.update!(custom_attributes: { 'meta_anuncio' => 'Saia do aluguel — a partir de R$ 500/mês' })

      texto = service.send(:origem_context)

      expect(texto).to include('Saia do aluguel — a partir de R$ 500/mês')
      expect(texto).to include('anúncio')
    end

    # A frase é o que impede o juiz de tratar a origem como palpite do avaliado.
    it 'tells the judge the origin is a legitimate source, not invention' do
      conversation.update!(custom_attributes: { 'meta_campanha' => 'Pacaembu' })

      expect(service.send(:origem_context)).to include('fonte legítima')
    end

    it 'includes every origin field that is filled' do
      conversation.update!(custom_attributes: { 'meta_anuncio' => 'Anúncio X', 'meta_origem' => 'Instagram',
                                                'jornada' => 'Interesse em locação' })

      texto = service.send(:origem_context)

      expect(texto).to include('Anúncio X').and include('Instagram').and include('Interesse em locação')
    end

    # Atributo vazio não pode virar linha: "anúncio: " sem valor sugere que houve anúncio e
    # ninguém sabe qual, que é pior que não falar nada.
    it 'skips blank values instead of emitting an empty line' do
      conversation.update!(custom_attributes: { 'meta_anuncio' => '  ', 'meta_origem' => 'Facebook' })

      texto = service.send(:origem_context)

      expect(texto).to include('Facebook')
      expect(texto).not_to include('anúncio')
    end

    it 'ignores attributes that are not about origin' do
      conversation.update!(custom_attributes: { 'codigos_buscados' => %w[123], 'rodizio_preferencia' => 'Gelson' })

      expect(service.send(:origem_context)).to be_nil
    end
  end

  # `transferencia_ausente` (IA -> outra IA) e `handoff_ausente` (IA -> humano) eram o mesmo
  # balde. Quem lê o relatório não distinguia "deixou o cliente sem gente" de "atendeu fora
  # da própria alçada", e a primeira é muito mais grave.
  describe 'categorias de falha' do
    let(:categorias) do
      Captain::ConversationEvalSchema.to_json_schema.to_s
    rescue StandardError
      Captain::ConversationEvalSchema.instance_variable_get(:@schema).to_s
    end

    it 'separates handing off to a human from routing to another AI' do
      expect(categorias).to include('handoff_ausente').and include('transferencia_ausente')
    end
  end
end
