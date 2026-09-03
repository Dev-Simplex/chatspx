# frozen_string_literal: true

require 'rails_helper'

# 6.05 — o RELATORIO, e principalmente a parte dele que um A/B mal feito sempre pula: dizer
# "ainda nao da para saber" em vez de exibir o maior numero.
RSpec.describe Flows::AbReportService do
  let(:account) { create(:account) }

  def variante(key, nodes: [], weight: nil)
    experiment = { 'key' => key }
    experiment['weight'] = weight unless weight.nil?
    create(:flow, account: account, trigger_type: :widget_prechat,
                  trigger_config: { 'experiment' => experiment },
                  definition: { 'nodes' => nodes, 'edges' => [] })
  end

  # Grava os fatos DIRETO na tabela do 5.03 — o relatorio nao conhece outra fonte, entao
  # este e o material dele. `dedup_key` unica por visitante e o que o AbTracking produziria.
  # `insert_all` e nao `create!` em laco: os exemplos de significancia precisam de milhares
  # de linhas (é o ponto deles — amostra grande), e linha a linha o arquivo levava 67 s.
  # Os campos que os callbacks preencheriam sao escritos aqui de proposito, porque o que se
  # esta montando e o ESTADO da tabela, nao o caminho de escrita (esse e testado no
  # ab_tracking_spec, com o EventRecorder de verdade).
  def registrar(name, flow, visitantes, node_id: nil, key: 'checkout')
    agora = Time.current
    linhas = visitantes.map do |v|
      propriedades = { 'experiment' => key, 'variant' => flow.id, 'variant_version' => flow.version }
      propriedades['node_id'] = node_id if node_id
      { event_id: SecureRandom.uuid, name: name, account_id: account.id, occurred_at: agora,
        source: 0, properties: propriedades, dedup_key: "flow_ab:#{flow.id}:#{v}:#{name}:#{node_id}",
        created_at: agora, updated_at: agora }
    end
    TrackingEvent.insert_all(linhas) if linhas.any? # rubocop:disable Rails/SkipsModelValidations
  end

  def expor(flow, quantos, key: 'checkout')
    registrar(Flows::AbTracking::ASSIGNED, flow, visitantes(flow, quantos), key: key)
  end

  def converter(flow, quantos, key: 'checkout')
    registrar(Flows::AbTracking::CONVERTED, flow, visitantes(flow, quantos), key: key)
  end

  # Os MESMOS visitantes: quem converte e um subconjunto de quem foi exposto, nunca gente
  # nova. Numerador fora do denominador daria taxa acima de 100%.
  def visitantes(flow, quantos)
    (1..quantos).map { |i| "#{flow.id}-v#{i}" }
  end

  def relatorio(key = 'checkout')
    described_class.new(account: account, experiment: key).perform
  end

  describe 'the numbers per variant' do
    it 'reports exposures, conversions and the rate for each arm' do
      a = variante('checkout')
      b = variante('checkout')
      expor(a, 100)
      converter(a, 25)
      expor(b, 100)
      converter(b, 40)

      variantes = relatorio['variants']
      expect(variantes.map { |v| v['exposures'] }).to eq([100, 100])
      expect(variantes.map { |v| v['conversions'] }).to eq([25, 40])
      expect(variantes.map { |v| v['conversion_rate'] }).to eq([25.0, 40.0])
    end

    it 'shows the variant that received nobody, instead of hiding the arm with no traffic' do
      a = variante('checkout')
      pausada = variante('checkout', weight: 0)
      expor(a, 40)

      pausada_no_relatorio = relatorio['variants'].find { |v| v['variant'] == pausada.id }
      expect(pausada_no_relatorio['exposures']).to eq(0)
      expect(pausada_no_relatorio['conversion_rate']).to eq(0.0)
      expect(pausada_no_relatorio['weight']).to eq(0)
    end

    it 'names the oldest arm as the control' do
      a = variante('checkout')
      b = variante('checkout')

      expect(relatorio['variants'].find { |v| v['control'] }['variant']).to eq(a.id)
      expect(relatorio['variants'].find { |v| v['variant'] == b.id }['control']).to be(false)
    end

    it 'keeps the version under which each arm was measured' do
      a = variante('checkout')
      a.update!(version: 3)
      expor(a, 10)

      expect(relatorio['variants'].first['version']).to eq(3)
    end
  end

  describe 'the funnel — where the visitor stopped' do
    let(:nodes) do
      [{ 'id' => 'nome', 'type' => 'action', 'label' => 'Pergunta o nome' },
       { 'id' => 'email', 'type' => 'action', 'label' => 'Pergunta o e-mail' },
       { 'id' => 'fim', 'type' => 'action', 'label' => 'Agradece' }]
    end

    it 'orders the steps by the flow definition and reports the drop at each one' do
      a = variante('checkout', nodes: nodes)
      expor(a, 100)
      registrar(Flows::AbTracking::STEP, a, (1..90).map { |i| "s#{i}" }, node_id: 'nome')
      registrar(Flows::AbTracking::STEP, a, (1..40).map { |i| "s#{i}" }, node_id: 'email')
      registrar(Flows::AbTracking::STEP, a, (1..35).map { |i| "s#{i}" }, node_id: 'fim')

      etapas = relatorio['variants'].first['steps']
      expect(etapas.map { |e| e['node_id'] }).to eq(%w[nome email fim])
      expect(etapas.map { |e| e['reached'] }).to eq([90, 40, 35])
      # A maior queda e do nome para o e-mail: 50 visitantes pararam ali.
      expect(etapas.map { |e| e['abandoned'] }).to eq([10, 50, 5])
    end

    it 'reads the funnel of each arm separately — which is the whole point of the test' do
      a = variante('checkout', nodes: nodes)
      b = variante('checkout', nodes: nodes)
      expor(a, 50)
      expor(b, 50)
      registrar(Flows::AbTracking::STEP, a, (1..10).map { |i| "a#{i}" }, node_id: 'email')
      registrar(Flows::AbTracking::STEP, b, (1..45).map { |i| "b#{i}" }, node_id: 'email')

      por_variante = relatorio['variants'].to_h do |v|
        [v['variant'], v['steps'].find { |e| e['node_id'] == 'email' }&.dig('reached')]
      end
      expect(por_variante[a.id]).to eq(10)
      expect(por_variante[b.id]).to eq(45)
    end
  end

  # ─── O ACEITE QUE IMPORTA ──────────────────────────────────────────────────────────
  describe 'the statistical honesty' do
    it 'refuses to crown a winner on a tiny sample, however big the apparent difference' do
      a = variante('checkout')
      b = variante('checkout')
      expor(a, 12)
      converter(a, 2)
      expor(b, 12)
      converter(b, 8) # 4x a taxa do controle — e ainda assim nao da para saber

      comparacao = relatorio['comparisons'].first
      expect(comparacao['verdict']).to eq('inconclusivo')
      expect(comparacao['reason']).to eq('amostra_insuficiente')
      expect(comparacao['min_exposures']).to eq(30)
    end

    it 'refuses when the arms are big enough but the successes are too few for the normal approximation' do
      a = variante('checkout')
      b = variante('checkout')
      expor(a, 200)
      converter(a, 1)
      expor(b, 200)
      converter(b, 4)

      comparacao = relatorio['comparisons'].first
      expect(comparacao['verdict']).to eq('inconclusivo')
      expect(comparacao['reason']).to eq('aproximacao_nao_vale')
    end

    it 'declares a small difference on a big sample as still inside chance' do
      a = variante('checkout')
      b = variante('checkout')
      expor(a, 1000)
      converter(a, 300)
      expor(b, 1000)
      converter(b, 315) # 30,0% contra 31,5%

      comparacao = relatorio['comparisons'].first
      expect(comparacao['verdict']).to eq('inconclusivo')
      expect(comparacao['reason']).to eq('diferenca_dentro_do_acaso')
      expect(comparacao['z'].abs).to be < 1.96
    end

    it 'does declare a winner when the sample and the difference are both there' do
      a = variante('checkout')
      b = variante('checkout')
      expor(a, 1000)
      converter(a, 300)
      expor(b, 1000)
      converter(b, 420) # 30% contra 42%

      comparacao = relatorio['comparisons'].first
      expect(comparacao['verdict']).to eq('melhor_que_o_controle')
      expect(comparacao['z'].abs).to be > 1.96
      expect(comparacao['p_value']).to be < 0.05
      expect(comparacao['lift']).to eq(40.0)
    end

    it 'declares the target WORSE when it is the control that wins' do
      a = variante('checkout')
      b = variante('checkout')
      expor(a, 1000)
      converter(a, 420)
      expor(b, 1000)
      converter(b, 300)

      expect(relatorio['comparisons'].first['verdict']).to eq('pior_que_o_controle')
    end

    it 'reports no lift at all instead of an infinite one when the control converted nobody' do
      a = variante('checkout')
      b = variante('checkout')
      expor(a, 100)
      expor(b, 100)
      converter(b, 30)

      expect(relatorio['comparisons'].first['lift']).to be_nil
    end

    it 'compares every arm against the control, and never all against all' do
      variante('checkout')
      variante('checkout')
      variante('checkout')

      expect(relatorio['comparisons'].size).to eq(2)
    end
  end

  describe 'isolation between experiments' do
    it 'never counts the events of another experiment' do
      a = variante('checkout')
      outro = variante('newsletter')
      expor(a, 40)
      expor(outro, 500, key: 'newsletter')

      expect(relatorio['variants'].map { |v| v['variant'] }).to eq([a.id])
      expect(relatorio['variants'].first['exposures']).to eq(40)
    end
  end
end
