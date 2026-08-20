require 'rails_helper'

# Bloco 1.22 — o endpoint que a tela consome.
RSpec.describe 'Relatório de origem das conversas (1.22)', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:since) { 30.days.ago }
  let(:until_time) { Time.current }

  def buscar(usuario: admin)
    get "/api/v2/accounts/#{account.id}/origin_report",
        params: { since: since.to_i.to_s, until: until_time.to_i.to_s },
        headers: usuario.create_new_auth_token, as: :json
    response
  end

  it 'exige autenticação' do
    get "/api/v2/accounts/#{account.id}/origin_report", as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'é relatório: agente não vê' do
    resposta = buscar(usuario: agent)

    # `ReportPolicy#view?` só passa para administrador. O que interessa ao aceite é que o agente
    # não recebe o relatório — a rota existe, provado pelo exemplo abaixo, em que o admin faz 200.
    expect(resposta).to have_http_status(:unauthorized)
    expect(resposta.body).not_to include('measurement_started_at')
  end

  context 'when a medição já começou' do
    before do
      travel_to(10.days.ago) { Tracking::OriginDefinitionsSeeder.new(account).perform }
      create(:conversation, account: account, inbox: inbox, created_at: 20.days.ago)
      create(:conversation, account: account, inbox: inbox, created_at: 5.days.ago,
                            custom_attributes: { 'last_utm_source' => 'google', 'last_utm_medium' => 'cpc',
                                                 'last_utm_campaign' => 'verao', 'last_origin_kind' => 'busca_paga' })
      create(:conversation, account: account, inbox: inbox, created_at: 4.days.ago,
                            custom_attributes: { 'last_origin_kind' => 'nao_disponivel' })
    end

    it 'devolve as contagens, o marco e o período anterior contado' do
      corpo = buscar.parsed_body

      expect(response).to have_http_status(:success)
      expect(corpo['measurement_started_at']).to be_present
      expect(corpo['before_measurement']['conversations_count']).to eq(1)
      expect(corpo['before_measurement']['covers_whole_range']).to be(false)
      expect(corpo['measured']['conversations_count']).to eq(2)
      expect(corpo['measured']['source']).to contain_exactly({ 'value' => 'google', 'count' => 1 }, { 'value' => nil, 'count' => 1 })
      # `nao_disponivel` chega ao cliente como ausência (`value: null`), na mesma linha de quem
      # nem passou pelo parser — duas linhas com o mesmo rótulo pareceriam tela quebrada.
      expect(corpo['measured']['origin_kind']).to contain_exactly(
        { 'value' => 'busca_paga', 'count' => 1 }, { 'value' => nil, 'count' => 1 }
      )
    end

    it 'não vaza o valor de máquina "nao_disponivel" para o cliente' do
      expect(buscar.parsed_body['measured']['origin_kind'].pluck('value')).not_to include('nao_disponivel')
    end

    it 'em lugar nenhum da resposta aparece a palavra "direta"' do
      expect(buscar.body).not_to include('direta')
    end
  end

  context 'when a conta nunca foi medida' do
    before { create(:conversation, account: account, inbox: inbox, created_at: 5.days.ago) }

    it 'devolve o período inteiro como "antes da medição", com a conversa contada' do
      corpo = buscar.parsed_body

      expect(corpo['measurement_started_at']).to be_nil
      expect(corpo['before_measurement']['conversations_count']).to eq(1)
      expect(corpo['before_measurement']['covers_whole_range']).to be(true)
      expect(corpo['measured']['conversations_count']).to eq(0)
    end
  end
end
