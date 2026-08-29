# frozen_string_literal: true

require 'rails_helper'

# 4.18 — "a retencao do registro parcial e CONFIGURAVEL, com padrao declarado".
#
# As quatro decisoes existiam com padrao e clamp desde o miolo e nao tinham porta: so davam
# para mexer por console do servidor. Uma retencao de dado pessoal que so a infraestrutura
# consegue mudar nao e configuravel — e a nota de LGPD do bloco e explicita sobre de quem e
# esse dado (de quem NAO consentiu com nada).
RSpec.describe 'Api::V1::Accounts::PartialLeadSettings', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/partial_lead_settings" }

  after { Current.reset }

  describe 'GET' do
    it 'devolve os padroes DECLARADOS numa conta que nunca configurou nada' do
      # A tela desenha o que o servidor vai fazer. Devolver o hash cru (vazio) faria a tela
      # mostrar campo em branco e o administrador concluir que nao ha retencao nenhuma.
      get url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to eq(
        'partial_lead_capture_enabled' => false,
        'partial_lead_abandon_after_minutes' => 5,
        'partial_lead_retention_days' => 30,
        'partial_lead_label' => 'lead-incompleto'
      )
    end

    it 'devolve o que a conta configurou' do
      account.update!(internal_attributes: { 'partial_lead_capture_enabled' => true,
                                             'partial_lead_retention_days' => 7 })

      get url, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to include(
        'partial_lead_capture_enabled' => true,
        'partial_lead_retention_days' => 7
      )
    end

    it 'nao responde a quem nao entrou' do
      get url, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'nao responde ao agente — a chave decide se dado pessoal de terceiro passa a ser guardado' do
      get url, headers: agent.create_new_auth_token, as: :json

      # 401, e nao 403: nesta base o Pundit nega com "nao autorizado". O que separa "a policy
      # negou" de "a rota nao existe" e o exemplo do administrador logo acima, que devolve 200
      # nesta mesma URL — sem ele, um 404 por rota errada satisfaria esta assercao.
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH' do
    it 'liga a captura e a decisao chega ao SERVICO, nao so ao banco' do
      # A assercao que importa nao e "o jsonb tem a chave": e o `RecordService` passar a
      # gravar. Sem esta ponte a tela ligaria uma chave que ninguem le.
      patch url, params: { partial_lead_capture_enabled: true }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(Widget::PartialLeads::Settings.new(account.reload)).to be_enabled
    end

    it 'grava a retencao e a janela de abandono' do
      patch url, params: { partial_lead_retention_days: 7, partial_lead_abandon_after_minutes: 15 },
                 headers: admin.create_new_auth_token, as: :json

      settings = Widget::PartialLeads::Settings.new(account.reload)
      expect(settings.retention_days).to eq(7)
      expect(settings.abandon_after_minutes).to eq(15)
    end

    it 'NORMALIZA na escrita: valor torto nao fica guardado parecendo valido' do
      # A leitura ja tinha clamp, entao "para sempre" nunca viraria retencao infinita. O que
      # faltava era a escrita: com o texto guardado, a tela mostraria "para sempre" de volta e
      # o administrador acreditaria numa configuracao que o servidor ignora.
      patch url, params: { partial_lead_retention_days: 'para sempre', partial_lead_abandon_after_minutes: -3 },
                 headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to include(
        'partial_lead_retention_days' => 30,
        'partial_lead_abandon_after_minutes' => 1
      )
      expect(account.reload.internal_attributes['partial_lead_retention_days']).to eq(30)
    end

    it 'trava a retencao no teto — dado de quem nao consentiu nao fica um ano e meio' do
      patch url, params: { partial_lead_retention_days: 5000 }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['partial_lead_retention_days']).to eq(365)
    end

    it 'normaliza a etiqueta para o que o painel consegue representar' do
      patch url, params: { partial_lead_label: '  Lead Perdido!  ' }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['partial_lead_label']).to eq('lead-perdido')
    end

    it 'etiqueta vazia DESLIGA a etiqueta, e nao volta ao padrao' do
      patch url, params: { partial_lead_label: '' }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['partial_lead_label']).to eq('')
      expect(Widget::PartialLeads::Settings.new(account.reload).label).to eq('')
    end

    it 'mexe SO nas quatro chaves: nao e uma porta para o resto de internal_attributes' do
      # `internal_attributes` guarda assunto de outros blocos (`flows_engine_enabled`). Um
      # `merge` do corpo cru deixaria a tela do lead incompleto ligar o motor de flows da conta.
      account.update!(internal_attributes: { 'flows_engine_enabled' => true })

      patch url, params: { partial_lead_capture_enabled: true, flows_engine_enabled: false },
                 headers: admin.create_new_auth_token, as: :json

      expect(account.reload.internal_attributes['flows_engine_enabled']).to be(true)
      expect(account.internal_attributes['partial_lead_capture_enabled']).to be(true)
    end

    it 'o AGENTE nao configura, e a configuracao da conta nao muda' do
      patch url, params: { partial_lead_capture_enabled: true }, headers: agent.create_new_auth_token, as: :json

      # 401, e nao 403: nesta base o Pundit nega com "nao autorizado". O que separa "a policy
      # negou" de "a rota nao existe" e o exemplo do administrador logo acima, que devolve 200
      # nesta mesma URL — sem ele, um 404 por rota errada satisfaria esta assercao.
      expect(response).to have_http_status(:unauthorized)
      expect(Widget::PartialLeads::Settings.new(account.reload)).not_to be_enabled
    end
  end
end
