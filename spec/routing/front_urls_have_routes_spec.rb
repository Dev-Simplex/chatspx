require 'rails_helper'

# Guarda de contrato entre o FRONT e as ROTAS.
#
# Motivo: `useTrackingCredentials.js` montava
#   /api/v1/accounts/:id/inboxes/:inbox_id/tracking_credentials   (plural)
# enquanto a rota e `resource :tracking_credential` (SINGULAR, porque ha no maximo uma por
# inbox). Toda chamada dava 404, e NENHUM teste pegava:
#   - o spec do front dubla a chamada HTTP, entao nunca toca a rota;
#   - o spec do backend chama o controller direto, entao nunca monta a URL.
# So apareceu em navegador real, com o backend integrado no ar.
#
# Esta guarda le a URL que o front escreve e pergunta ao roteador do Rails se ela existe.
# Ela falha se alguem trocar a rota de singular para plural, ou vice-versa, sem acertar o outro lado.
# arquivo do front => lista de [metodo, caminho com :id substituido]
FRONT_URL_CONTRACTS = {
  'app/javascript/dashboard/routes/dashboard/settings/inbox/widget/tracking/useTrackingCredentials.js' => [
    [:get,   '/api/v1/accounts/1/inboxes/2/tracking_credential'],
    [:patch, '/api/v1/accounts/1/inboxes/2/tracking_credential'],
    [:post,  '/api/v1/accounts/1/inboxes/2/tracking_credential/verify'],
    # PUT no RECURSO, com o objeto no corpo — nao uma rota por chave. O front montava
    # `PUT .../tracking_credential/<chave>` e essa rota nunca existiu; o spec do front
    # ficava verde porque o dublê casava a URL por `includes`.
    [:put,   '/api/v1/accounts/1/inboxes/2/tracking_credential']
  ],
  # Bloco 5.14 — o painel de diagnostico. Estas duas eram chamadas contra um roteador que
  # NAO as tinha: 404 nas duas, medido em navegador. Aqui o PLURAL e o certo (ha muitas
  # entregas por inbox), o oposto do caso acima — e e exatamente por os dois casos serem
  # opostos que nenhum deles pode ser decidido de cabeca.
  'app/javascript/dashboard/routes/dashboard/settings/inbox/widget/tracking/trackingDiagnosticsApi.js' => [
    [:get,  '/api/v1/accounts/1/inboxes/2/tracking_deliveries'],
    [:post, '/api/v1/accounts/1/inboxes/2/tracking_deliveries/test']
  ],
  # Bloco 4.14 — as acoes de membro do webhook. O CRUD ja existia; estas tres sao o log de
  # entregas, o reenvio e a rotacao do segredo, e todas sao POST/GET em `/:id/<acao>`.
  'app/javascript/dashboard/api/webhooks.js' => [
    [:get,  '/api/v1/accounts/1/webhooks/2/deliveries'],
    [:post, '/api/v1/accounts/1/webhooks/2/replay'],
    [:post, '/api/v1/accounts/1/webhooks/2/rotate_secret']
  ]
}.freeze

RSpec.describe 'URLs que o front monta tem rota no Rails', type: :routing do
  it 'nao esta vazia — senao esta guarda passa medindo zero' do
    expect(FRONT_URL_CONTRACTS.values.flatten(1).size).to be >= 3
  end

  FRONT_URL_CONTRACTS.each do |arquivo, chamadas|
    context arquivo do
      it 'existe no repo (senao o contrato esta descrevendo um arquivo morto)' do
        expect(Rails.root.join(arquivo)).to exist
      end

      chamadas.each do |verbo, caminho|
        it "roteia #{verbo.to_s.upcase} #{caminho}" do
          expect(verbo => caminho).to be_routable
        end
      end
    end
  end

  it 'a rota POR CHAVE, que o front inventou, continua sem existir' do
    expect(put: '/api/v1/accounts/1/inboxes/2/tracking_credential/meta_access_token').not_to be_routable
  end

  it 'o caminho PLURAL, que era o defeito, continua sem rota' do
    expect(get: '/api/v1/accounts/1/inboxes/2/tracking_credentials').not_to be_routable
  end

  # O espelho do caso acima, e a razao de ele estar escrito: em `tracking_deliveries` o
  # plural e que e o certo. Trocar um pelo outro "para ficar igual ao vizinho" reproduz o
  # mesmo 404 pelo motivo inverso.
  it 'o SINGULAR de tracking_delivery nao existe — aqui o plural e que e o certo' do
    expect(get: '/api/v1/accounts/1/inboxes/2/tracking_delivery').not_to be_routable
  end

  # `replay` e `rotate_secret` sao acoes de MEMBRO. Como acao de colecao elas roteariam para
  # o webhook de id "replay", que responderia 404 de registro — um 404 que se le como
  # "webhook nao existe" em vez de "a rota esta errada", que e a pior forma de errar.
  it 'as acoes do webhook sao de MEMBRO, nao de colecao' do
    expect(post: '/api/v1/accounts/1/webhooks/replay').not_to be_routable
    expect(post: '/api/v1/accounts/1/webhooks/rotate_secret').not_to be_routable
  end
end
