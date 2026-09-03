# frozen_string_literal: true

require 'rails_helper'

# 4.18 — a porta do relatorio. O aceite ("quantos leads perdemos e onde") e medido no
# servico; aqui garantimos que ele e ALCANCAVEL, autorizado, escopado na conta e — a
# parte que protege o cliente — que ele nao devolve as RESPOSTAS de quem nao concluiu.
RSpec.describe 'Api::V2::Accounts::PartialLeadReports', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:web_widget) { create(:channel_widget, account: account) }

  before do
    create(:widget_partial_lead, account: account, inbox: web_widget.inbox,
                                 step_reached: 3, step_key: 'phoneNumber',
                                 answers: { 'emailAddress' => 'segredo@empresa.com.br' })
    create(:widget_partial_lead, account: account, inbox: web_widget.inbox, step_reached: 4, completed_at: Time.current)
  end

  it 'recusa quem nao esta autenticado' do
    get "/api/v2/accounts/#{account.id}/partial_lead_report"

    expect(response).to have_http_status(:unauthorized)
  end

  it 'devolve quantos e onde para o administrador' do
    get "/api/v2/accounts/#{account.id}/partial_lead_report",
        headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    corpo = response.parsed_body
    expect(corpo['started']).to eq(2)
    expect(corpo['completed']).to eq(1)
    expect(corpo['abandoned']).to eq(1)
    expect(corpo['by_step']).to eq({ '3' => 1 })
    expect(corpo['by_step_name']).to eq({ 'phoneNumber' => 1 })
  end

  it 'NAO devolve as respostas do visitante — o relatorio conta, nao expoe' do
    get "/api/v2/accounts/#{account.id}/partial_lead_report",
        headers: administrator.create_new_auth_token, as: :json

    expect(response.body).not_to include('segredo@empresa.com.br')
    expect(response.body).not_to include('answers')
  end

  it 'escopa por inbox e ignora inbox de outra conta' do
    outra_conta = create(:account)
    inbox_alheia = create(:channel_widget, account: outra_conta).inbox
    create(:widget_partial_lead, account: outra_conta, inbox: inbox_alheia)

    get "/api/v2/accounts/#{account.id}/partial_lead_report",
        params: { inbox_id: inbox_alheia.id }, headers: administrator.create_new_auth_token, as: :json

    # Inbox de outra conta nao filtra nada nem vaza nada: devolve o relatorio da conta atual.
    expect(response.parsed_body['started']).to eq(2)
  end

  # MEDIDO, e a expectativa inicial estava errada: `ReportPolicy#view?` e
  # `@account_user.administrator?`. O agente NAO ve relatorio nenhum neste produto, e o
  # de lead perdido segue a mesma regra — nao invento uma permissao mais frouxa para o
  # dado de quem nem virou conversa.
  it 'recusa o agente, como todos os demais relatorios' do
    get "/api/v2/accounts/#{account.id}/partial_lead_report",
        headers: agent.create_new_auth_token, as: :json

    expect(response).not_to have_http_status(:success)
  end
end
