# frozen_string_literal: true

require 'rails_helper'

# 6.05 — a DESIGNACAO. O que se prova aqui e que ela nao e sorteio: e funcao pura de
# (chave do experimento, chave do visitante), e por isso o mesmo visitante cai sempre na
# mesma variante.
RSpec.describe Flow::AbExperiment do
  let(:account) { create(:account) }

  def variante(key, weight: nil)
    experiment = { 'key' => key }
    experiment['weight'] = weight unless weight.nil?
    create(:flow, account: account, trigger_type: :widget_prechat,
                  trigger_config: { 'experiment' => experiment })
  end

  describe '.key_for' do
    it 'reads the key a flow declares' do
      expect(described_class.key_for(variante('prechat-curto'))).to eq('prechat-curto')
    end

    it 'is nil for a flow that declares no experiment — the state of the whole fleet today' do
      flow = create(:flow, account: account, trigger_type: :widget_prechat, trigger_config: {})

      expect(described_class.key_for(flow)).to be_nil
    end

    it 'is nil when the key is present but blank, instead of grouping every blank flow together' do
      flow = create(:flow, account: account, trigger_type: :widget_prechat,
                           trigger_config: { 'experiment' => { 'key' => '  ' } })

      expect(described_class.key_for(flow)).to be_nil
    end
  end

  describe '.weight_for' do
    it 'defaults to 50 when the flow declares no weight' do
      expect(described_class.weight_for(variante('x'))).to eq(50)
    end

    it 'accepts 0 — the way to pause a variant without deleting its history' do
      expect(described_class.weight_for(variante('x', weight: 0))).to eq(0)
    end

    # Os dois casos abaixo escrevem DIRETO na coluna, contornando a validacao de proposito:
    # o schema ja recusa isto na escrita (medido no spec do 4.02), entao o unico jeito de a
    # linha existir e ela ser anterior ao schema ou ter vindo por outro caminho. O
    # saneamento e a rede para essa linha — sem ele um `weight` torto derruba a designacao
    # inteira da conta pelo `rescue` do resolver.
    it 'clamps a weight above the ceiling instead of letting it swallow the split' do
      flow = variante('x')
      # rubocop:disable Rails/SkipsModelValidations -- pular a validacao E o cenario: a
      # linha so existe se for anterior ao schema ou tiver vindo por outro caminho.
      flow.update_column(:trigger_config, { 'experiment' => { 'key' => 'x', 'weight' => 5000 } })
      # rubocop:enable Rails/SkipsModelValidations

      expect(described_class.weight_for(flow.reload)).to eq(100)
    end

    it 'falls back to the default when the weight is garbage, rather than reading it as zero' do
      flow = variante('x')
      # rubocop:disable Rails/SkipsModelValidations -- mesma razao do exemplo acima.
      flow.update_column(:trigger_config, { 'experiment' => { 'key' => 'x', 'weight' => 'muito' } })
      # rubocop:enable Rails/SkipsModelValidations

      expect(described_class.weight_for(flow.reload)).to eq(50)
    end
  end

  describe '.assign' do
    let!(:a) { variante('checkout') }
    let!(:b) { variante('checkout') }
    let(:variants) { [a, b] }

    it 'gives the same visitor the same variant every single time' do
      escolhas = Array.new(20) { described_class.assign(variants: variants, visitor_key: 'visitante-1') }

      expect(escolhas.uniq.size).to eq(1)
      expect(variants).to include(escolhas.first)
    end

    it 'splits visitors across both variants — it is a split, not a constant' do
      escolhidos = (1..200).map do |n|
        described_class.assign(variants: variants, visitor_key: "visitante-#{n}")&.id
      end

      expect(escolhidos.uniq.sort).to eq([a.id, b.id].sort)
    end

    it 'sends roughly half the traffic to each arm at 50/50' do
      no_a = (1..400).count do |n|
        described_class.assign(variants: variants, visitor_key: "v-#{n}") == a
      end

      # 400 visitantes num 50/50 tem desvio padrao 10, entao 160..240 e 4 sigma. Exigir
      # exatamente 200 seria testar sorte, nao distribuicao.
      expect(no_a).to be_between(160, 240)
    end

    it 'sends nobody to a variant paused at weight 0, and everybody to the live one' do
      pausada = variante('promo', weight: 0)
      viva = variante('promo', weight: 100)

      escolhidos = (1..50).map { |n| described_class.assign(variants: [pausada, viva], visitor_key: "v-#{n}") }

      expect(escolhidos.uniq).to eq([viva])
    end

    it 'assigns nobody when every arm is paused, instead of dividing by zero or electing the first' do
      duas_pausadas = [variante('promo', weight: 0), variante('promo', weight: 0)]

      expect(described_class.assign(variants: duas_pausadas, visitor_key: 'v-1')).to be_nil
    end

    # O ACEITE: sem chave estavel, NAO se sorteia.
    it 'refuses to assign when the visitor has no stable key — a lottery would poison both arms' do
      expect(described_class.assign(variants: variants, visitor_key: nil)).to be_nil
      expect(described_class.assign(variants: variants, visitor_key: '')).to be_nil
    end

    it 'keeps two experiments independent — the same visitor is not always in arm B of everything' do
      outro = [variante('newsletter'), variante('newsletter')]

      pares = (1..120).map do |n|
        chave = "visitante-#{n}"
        [variants.index(described_class.assign(variants: variants, visitor_key: chave)),
         outro.index(described_class.assign(variants: outro, visitor_key: chave))]
      end

      # Sem a chave do experimento no hash os dois indices seriam sempre iguais e este
      # conjunto teria 2 elementos. Com ela, aparecem as quatro combinacoes.
      expect(pares.uniq.size).to eq(4)
    end
  end

  describe '.variants' do
    it 'groups only the flows that share the key, in stable id order' do
      primeiro = variante('checkout')
      segundo = variante('checkout')
      alheio = variante('outro')

      expect(described_class.variants([segundo, alheio, primeiro], 'checkout')).to eq([primeiro, segundo])
    end
  end
end
