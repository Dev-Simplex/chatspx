# frozen_string_literal: true

require 'rails_helper'

# 6.05 — a porta de leitura do teste A/B. O calculo e testado em
# spec/services/flows/ab_report_service_spec.rb; aqui ficam a autorizacao, a janela e a
# forma do JSON que a tela consome.
RSpec.describe 'Api::V1::Accounts::FlowsController#experiment', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }

  def variante(key = 'checkout')
    create(:flow, account: account, trigger_type: :widget_prechat,
                  trigger_config: { 'experiment' => { 'key' => key } })
  end

  def expor(flow, quantidade, name: Flows::AbTracking::ASSIGNED, quando: Time.current)
    linhas = (1..quantidade).map do |i|
      { event_id: SecureRandom.uuid, name: name, account_id: account.id, occurred_at: quando,
        source: 0, properties: { 'experiment' => 'checkout', 'variant' => flow.id, 'variant_version' => flow.version },
        dedup_key: "flow_ab:#{flow.id}:#{i}:#{name}:#{quando.to_i}", created_at: quando, updated_at: quando }
    end
    TrackingEvent.insert_all(linhas) # rubocop:disable Rails/SkipsModelValidations
  end

  def buscar(params = { key: 'checkout' }, como: administrator)
    get "/api/v1/accounts/#{account.id}/flows/experiment", params: params, headers: como.create_new_auth_token
  end

  describe 'authorization' do
    it 'refuses an unauthenticated request' do
      get "/api/v1/accounts/#{account.id}/flows/experiment", params: { key: 'checkout' }

      expect(response).to have_http_status(:unauthorized)
    end

    # `index?` e nao `show?`: o experimento e do CONJUNTO de variantes, e exigir a autoria de
    # uma delas negaria o numero a quem nao criou aquele flow.
    it 'lets an agent who can list the flows read the experiment result' do
      variante
      buscar(como: agente)

      expect(response).to have_http_status(:success)
    end
  end

  describe 'the shape the screen consumes' do
    it 'returns the arms with their numbers and the comparison against the control' do
      a = variante
      b = variante
      expor(a, 1000)
      expor(a, 300, name: Flows::AbTracking::CONVERTED)
      expor(b, 1000)
      expor(b, 420, name: Flows::AbTracking::CONVERTED)

      buscar
      corpo = response.parsed_body

      expect(corpo['experiment']).to eq('checkout')
      expect(corpo['variants'].map { |v| v['variant'] }).to eq([a.id, b.id])
      expect(corpo['variants'].map { |v| v['conversion_rate'] }).to eq([30.0, 42.0])
      expect(corpo['comparisons'].first['verdict']).to eq('melhor_que_o_controle')
    end

    it 'says inconclusive out loud instead of returning the bigger number alone' do
      a = variante
      b = variante
      expor(a, 12)
      expor(a, 2, name: Flows::AbTracking::CONVERTED)
      expor(b, 12)
      expor(b, 8, name: Flows::AbTracking::CONVERTED)

      buscar
      comparacao = response.parsed_body['comparisons'].first

      expect(comparacao['verdict']).to eq('inconclusivo')
      expect(comparacao['reason']).to eq('amostra_insuficiente')
    end

    it 'refuses without the experiment key, instead of reporting an empty experiment' do
      buscar({})

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'the window' do
    it 'reads the whole history when no dates are given — an old experiment stays readable' do
      a = variante
      expor(a, 40, quando: 6.months.ago)

      buscar
      expect(response.parsed_body['variants'].first['exposures']).to eq(40)
    end

    it 'counts only what falls inside the window when dates are given' do
      a = variante
      expor(a, 40, quando: 6.months.ago)
      expor(a, 10, quando: 2.days.ago)

      buscar({ key: 'checkout', since: 7.days.ago.iso8601, until: Time.current.iso8601 })
      expect(response.parsed_body['variants'].first['exposures']).to eq(10)
    end

    it 'falls back to the whole history when the date is unreadable, rather than erroring out' do
      a = variante
      expor(a, 40, quando: 6.months.ago)

      buscar({ key: 'checkout', since: 'ontem de manha' })

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['variants'].first['exposures']).to eq(40)
    end
  end
end
