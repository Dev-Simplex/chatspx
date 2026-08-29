require 'rails_helper'

# Bloco 4.15 — a ROTA do relatorio de enforcement.
#
# O relatorio existia e respondia certo, mas so por console: nenhuma URL chegava nele. Os
# dois relatorios irmaos do mesmo plano (1.22 `origin_report`, 4.18 `partial_lead_report`)
# ganharam rota; este ficou sem, e um relatorio sem rota nao decide virada nenhuma porque
# ninguem que decide abre um console.
#
# A ARMADILHA QUE ESTE ARQUIVO EXISTE PARA TRAVAR e a mesma que ja custou 404 nesta base
# duas vezes (5.02 e 5.14): `resource :x` no SINGULAR gera `XsController` no PLURAL e serve
# `/x`. Quem le o `routes.rb` ve singular, quem escreve o front escreve plural, e o 404 sai
# uniforme — indistinguivel de "inbox nao existe". Por isso os exemplos abaixo exercitam a
# URL de verdade pelo roteador, e nao o controller direto.
RSpec.describe 'relatorio de enforcement de identidade — a rota', type: :request do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_widget, account: account) }
  let(:inbox) { channel.inbox }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def url(inbox_id = inbox.id)
    "/api/v1/accounts/#{account.id}/inboxes/#{inbox_id}/identity_enforcement_report"
  end

  def session(identity: {}, verified: false)
    contact = create(:contact, { account: account }.merge(identity))
    create(:contact_inbox, contact: contact, inbox: inbox, hmac_verified: verified)
  end

  describe 'a rota existe e responde o relatorio' do
    it 'devolve o relatorio da inbox com os numeros do servico' do
      session(identity: { email: 'a@corp.com' })
      session(identity: { phone_number: '+5565999990001' })
      session(identity: { email: 'b@corp.com' }, verified: true)
      session # anonima, fora da conta

      get url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      corpo = response.parsed_body
      expect(corpo['inbox_id']).to eq(inbox.id)
      expect(corpo['state']).to eq('desativado')
      expect(corpo['unverified']['total']).to eq(2)
      expect(corpo['rows'].size).to eq(2)
    end

    it 'devolve o estado RESOLVIDO, e nao o gravado' do
      inbox.update!(identity_enforcement: 'observado')

      get url, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['state']).to eq('observado')
      expect(response.parsed_body['observed_since']).to be_present
    end

    # A razao de o relatorio existir: separar o medido do historico. Sem marca de inicio
    # os dois contadores sao `nil`, e `nil` nao pode virar `0` na serializacao — zero
    # leria-se "nao houve nada" onde a verdade e "ninguem estava anotando".
    it 'sem observacao ligada, os contadores do corte saem NULOS e nao zerados' do
      session(identity: { email: 'a@corp.com' })

      get url, headers: admin.create_new_auth_token, as: :json

      corpo = response.parsed_body
      expect(corpo['unverified']['since_observation']).to be_nil
      expect(corpo['unverified']['before_observation']).to be_nil
      expect(corpo['unverified']['covers_whole_history']).to be(true)
    end
  end

  # O ACEITE do bloco 4.15, escrito no PLANO-MESTRE, inteiro e por HTTP:
  #
  #   "Ligar `observado` numa inbox com trafego produz a lista de identificacoes nao
  #    verificadas SEM quebrar nenhuma sessao."
  #
  # Ate esta trilha as duas metades eram medidas em arquivos diferentes: a sessao que nao
  # quebra no spec dos estados, a lista no spec do servico. Nenhum exemplo ligava as duas —
  # e nao havia como ligar, porque a lista nao tinha URL. Agora tem, e o exemplo abaixo faz
  # o percurso do administrador de verdade: liga o estado pela API da inbox, deixa um
  # visitante se identificar sem assinatura, e abre o relatorio.
  describe 'o aceite do bloco, por HTTP' do
    let(:visitante) do
      create(:contact_inbox, contact: create(:contact, account: account), inbox: inbox, hmac_verified: false)
    end
    let(:percurso) { percorrer_o_aceite }

    def ligar_observado
      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            params: { additional_attributes: { identity_enforcement: 'observado' } },
            headers: admin.create_new_auth_token,
            as: :json
    end

    # Um visitante se identifica SEM assinatura, com a observacao ja ligada.
    def identificar_sem_assinatura
      token = Widget::TokenService.new(payload: { source_id: visitante.source_id, inbox_id: inbox.id }).generate_token
      patch '/api/v1/widget/contact',
            params: { website_token: channel.website_token, email: 'novo@corp.com' },
            headers: { 'X-Auth-Token' => token },
            as: :json
    end

    # O percurso do administrador de verdade, na ordem em que ele acontece. Devolve o que
    # as duas metades do aceite precisam medir.
    def percorrer_o_aceite
      # A inbox JA tem trafego identificado sem assinatura antes de alguem observar.
      session(identity: { email: 'antigo@corp.com' })
      session # anonima: nao entra na conta em nenhum momento

      ligar_observado
      identificar_sem_assinatura
      status_do_visitante = response.status

      get url, headers: admin.create_new_auth_token, as: :json
      { status_do_visitante: status_do_visitante, relatorio: response.parsed_body }
    end

    it 'metade 1 — nenhuma sessao quebra, e o sinal do relatorio sobrevive' do
      expect(percurso[:status_do_visitante]).to eq(200)
      expect(visitante.reload.hmac_verified).to be(false)
    end

    it 'metade 2 — a lista sai por URL, com a identificacao recem-chegada dentro' do
      relatorio = percurso[:relatorio]

      expect(relatorio['state']).to eq('observado')
      expect(relatorio['observed_since']).to be_present
      expect(relatorio['unverified']['covers_whole_history']).to be(false)
      # As duas identificadas; a anonima fica de fora nos dois momentos.
      expect(relatorio['unverified']['total']).to eq(2)
      expect(relatorio['rows'].map { |row| row['contact_inbox_id'] }).to include(visitante.id)
    end
  end

  describe 'quem pode ler' do
    it 'recusa o agente comum — e relatorio, e relatorio e do administrador' do
      get url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'recusa quem nao esta autenticado' do
      get url, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    # Escopo: a inbox sai SEMPRE de `Current.account.inboxes`. Id de inbox de outra conta
    # e 404, nunca o relatorio alheio.
    it 'nao entrega o relatorio de inbox de outra conta' do
      alheia = create(:channel_widget, account: create(:account)).inbox

      get url(alheia.id), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
