require 'rails_helper'

RSpec.describe Tracking::OriginReport do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:since) { 30.days.ago }
  let(:until_time) { Time.current }

  def relatorio
    described_class.new(account: account, since: since, until_time: until_time).perform
  end

  def conversa(created_at:, origem: {})
    create(:conversation, account: account, inbox: inbox, created_at: created_at, custom_attributes: origem)
  end

  # A medição "começa" quando o 1.18 provisiona a conta. Nos testes, controlamos esse marco
  # criando as definições no instante que interessa.
  def iniciar_medicao_em(momento)
    travel_to(momento) { Tracking::OriginDefinitionsSeeder.new(account).perform }
  end

  describe 'when a conta nunca foi medida' do
    it 'não inventa medição: tudo é "antes da medição", e não é zero' do
      conversa(created_at: 5.days.ago)
      conversa(created_at: 3.days.ago)

      resultado = relatorio

      expect(resultado[:measurement_started_at]).to be_nil
      expect(resultado[:before_measurement][:conversations_count]).to eq(2)
      expect(resultado[:before_measurement][:covers_whole_range]).to be(true)
      expect(resultado[:measured][:conversations_count]).to eq(0)
    end
  end

  describe 'when o período começa antes da entrada da medição' do
    before { iniciar_medicao_em(10.days.ago) }

    it 'aparece contado, nunca vazio nem zerado' do
      conversa(created_at: 20.days.ago)
      conversa(created_at: 15.days.ago)
      conversa(created_at: 5.days.ago, origem: { 'last_utm_source' => 'google', 'last_origin_kind' => 'busca_paga' })

      resultado = relatorio

      expect(resultado[:before_measurement][:conversations_count]).to eq(2)
      expect(resultado[:before_measurement][:covers_whole_range]).to be(false)
      expect(resultado[:measured][:conversations_count]).to eq(1)
    end

    it 'não deixa a conversa antiga poluir a contagem por origem' do
      conversa(created_at: 20.days.ago)
      conversa(created_at: 5.days.ago, origem: { 'last_utm_source' => 'google' })

      expect(relatorio[:measured][:source]).to eq([{ value: 'google', count: 1 }])
    end
  end

  describe 'when há conversas medidas' do
    before { iniciar_medicao_em(10.days.ago) }

    it 'conta conversas por source, medium e campaign' do
      2.times do
        conversa(created_at: 5.days.ago,
                 origem: { 'last_utm_source' => 'google', 'last_utm_medium' => 'cpc', 'last_utm_campaign' => 'verao' })
      end
      conversa(created_at: 4.days.ago, origem: { 'last_utm_source' => 'meta', 'last_utm_medium' => 'social', 'last_utm_campaign' => 'verao' })

      resultado = relatorio[:measured]

      expect(resultado[:source]).to eq([{ value: 'google', count: 2 }, { value: 'meta', count: 1 }])
      expect(resultado[:medium]).to eq([{ value: 'cpc', count: 2 }, { value: 'social', count: 1 }])
      expect(resultado[:campaign]).to eq([{ value: 'verao', count: 3 }])
      expect(resultado[:conversations_count]).to eq(3)
    end

    it 'conta a conversa medida SEM origem como valor nulo — nunca como "direta"' do
      conversa(created_at: 5.days.ago, origem: { 'last_utm_source' => 'google' })
      2.times { conversa(created_at: 5.days.ago, origem: { 'last_origin_kind' => 'nao_disponivel' }) }

      linhas = relatorio[:measured][:source]

      expect(linhas).to contain_exactly({ value: 'google', count: 1 }, { value: nil, count: 2 })
      expect(linhas.pluck(:value)).not_to include('direta', 'direct')
      # o total fecha com o número de conversas medidas: nada some no caminho
      expect(linhas.sum { |linha| linha[:count] }).to eq(relatorio[:measured][:conversations_count])
    end

    it 'traz a classificação do 1.19, com ia_generativa como origem própria' do
      conversa(created_at: 5.days.ago, origem: { 'last_origin_kind' => 'ia_generativa' })
      conversa(created_at: 5.days.ago, origem: { 'last_origin_kind' => 'busca_paga' })

      expect(relatorio[:measured][:origin_kind]).to contain_exactly(
        { value: 'ia_generativa', count: 1 }, { value: 'busca_paga', count: 1 }
      )
    end

    # Defeito pego na validação em navegador: a tela mostrava DUAS linhas de indisponível na
    # dimensão de tipo — `nao_disponivel` (o parser rodou e não achou) e a ausência da chave (a
    # conversa nem passou pelo parser). Causas diferentes, mesma frase para o cliente.
    it 'soma "nao_disponivel" e ausência da chave numa linha só, em origin_kind' do
      3.times { conversa(created_at: 5.days.ago, origem: { 'last_origin_kind' => 'nao_disponivel' }) }
      2.times { conversa(created_at: 5.days.ago, origem: { 'last_utm_source' => 'google' }) }
      conversa(created_at: 5.days.ago, origem: { 'last_origin_kind' => 'busca_paga' })

      linhas = relatorio[:measured][:origin_kind]

      expect(linhas).to eq([{ value: nil, count: 5 }, { value: 'busca_paga', count: 1 }])
      expect(linhas.pluck(:value)).not_to include('nao_disponivel')
      expect(linhas.sum { |linha| linha[:count] }).to eq(relatorio[:measured][:conversations_count])
    end

    it 'a unificação não toca as outras dimensões — ali o valor do cliente é o dado' do
      conversa(created_at: 5.days.ago, origem: { 'last_utm_source' => 'nao_disponivel' })

      expect(relatorio[:measured][:source]).to eq([{ value: 'nao_disponivel', count: 1 }])
    end

    it 'respeita a janela pedida' do
      conversa(created_at: 40.days.ago, origem: { 'last_utm_source' => 'fora' })
      conversa(created_at: 5.days.ago, origem: { 'last_utm_source' => 'dentro' })

      expect(relatorio[:measured][:source]).to eq([{ value: 'dentro', count: 1 }])
      expect(relatorio[:before_measurement][:conversations_count]).to eq(0)
    end

    it 'não vaza conversa de outra conta' do
      outra_conta = create(:account)
      outra_inbox = create(:inbox, account: outra_conta)
      create(:conversation, account: outra_conta, inbox: outra_inbox, created_at: 5.days.ago,
                            custom_attributes: { 'last_utm_source' => 'vizinho' })
      conversa(created_at: 5.days.ago, origem: { 'last_utm_source' => 'nosso' })

      expect(relatorio[:measured][:source]).to eq([{ value: 'nosso', count: 1 }])
    end
  end
end
