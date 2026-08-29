# frozen_string_literal: true

require 'rails_helper'

# 4.21 — A JUNTA, ATRAVESSADA COM O CORPO REAL DO CLIENTE.
#
# `spec/controllers/api/v1/widget/approach_events_spec.rb` mede o servidor muito bem, e
# mesmo assim nao viu o defeito: o helper `registra` monta o `website_token` A MAO. O vitest
# vizinho media o cliente e dublava o `API.post`, congelando o corpo. Cada lado provou o seu
# lado, o corpo que sai do navegador nunca encostou no Rails, e o resultado em producao era
# 404 em toda chamada — engolido pelo `.catch(() => {})` do modulo. Nenhum evento de
# abordagem gravado, sem denominador nem numerador, com 21 exemplos verdes.
#
# ESTE spec nao monta payload. Ele LE a requisicao que o cliente de verdade poe na rede,
# capturada do proprio `widget/api/approachEvent.js` rodando sobre o axios de verdade em
# `app/javascript/widget/api/specs/approachEventJunta.spec.js`, e a envia ao Rails.
#
# So o VALOR do token e substituido, porque ele nasce da conta que este spec acabou de criar
# e o navegador nao teria como adivinha-lo. A CHAVE e o lugar dela vem da fixture — e era
# exatamente a chave que faltava.
RSpec.describe 'A junta do evento de abordagem (4.21)', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:contact) { create(:contact, account: account, email: nil, phone_number: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }

  # O `X-Auth-Token` NAO vem da fixture de proposito: quem o instala e o boot do widget
  # (`setHeader`), nao o modulo do bloco. O que a fixture guarda e o contrato DESTE modulo.
  let(:session_header) do
    token = Widget::TokenService.new(
      payload: { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id }
    ).generate_token
    { 'X-Auth-Token' => token }
  end

  let(:fixture) { JSON.parse(Rails.root.join('spec/fixtures/widget_approach_event_wire.json').read) }
  let(:sentinela) { fixture.fetch('sentinel_website_token') }
  let(:exibicao) { fixture['requests'].find { |r| r.dig('body', 'stage') == 'shown' } }
  let(:conversao) { fixture['requests'].find { |r| r.dig('body', 'stage') == 'converted' } }

  after { Current.reset }

  # Troca o sentinela pelo token do canal criado aqui, em qualquer profundidade e tanto na
  # query quanto no corpo — a fixture e quem decide onde o token mora, nao este spec.
  def com_token_real(valor)
    case valor
    when Hash then valor.transform_values { |v| com_token_real(v) }
    when Array then valor.map { |v| com_token_real(v) }
    when sentinela then web_widget.website_token
    else valor
    end
  end

  def envia(requisicao, headers: nil)
    query = com_token_real(requisicao['params'])
    url = requisicao['url']
    url = "#{url}?#{query.to_query}" if query.present?

    post url,
         params: com_token_real(requisicao['body']),
         headers: headers || session_header,
         as: :json
  end

  describe 'o corpo que o navegador poe na rede chega ao servidor' do
    it 'a EXIBICAO e aceita e vira um fato gravado' do
      expect { envia(exibicao) }.to change(TrackingEvent, :count).by(1)

      expect(response).to have_http_status(:no_content)
      expect(TrackingEvent.last.name).to eq('chatspx_approach_shown')
    end

    it 'a CONVERSAO tambem — sem os dois lados nao ha taxa nenhuma para comparar' do
      envia(exibicao)

      expect { envia(conversao) }.to change(TrackingEvent, :count).by(1)
      expect(response).to have_http_status(:no_content)
      expect(TrackingEvent.last.name).to eq('chatspx_approach_converted')
    end

    it 'o fato gravado carrega os niveis que o CLIENTE mandou, nao os que este spec escolheu' do
      envia(exibicao)

      corpo = exibicao['body']
      expect(TrackingEvent.last.properties).to eq(
        'approach' => corpo['approach'],
        'approach_configured' => corpo['approach_configured'],
        'degraded' => corpo['approach'] != corpo['approach_configured']
      )
    end

    it 'nada do corpo do cliente vaza para as propriedades do fato' do
      envia(exibicao)

      # `website_token` atravessa a junta e para no `BaseController`. Se um dia ele aparecer
      # aqui, o aceite «nenhum dado pessoal no payload» perde a guarda que o torna verificavel:
      # a lista de chaves deixa de ser fechada.
      expect(TrackingEvent.last.properties.keys).to contain_exactly('approach', 'approach_configured', 'degraded')
    end
  end

  # ── A CONDICAO RUIM, FORCADA ────────────────────────────────────────────────────────────
  #
  # Sem esta parte os exemplos acima seriam so «o corpo de hoje funciona». Ela prova que este
  # spec MEDE a junta: e o mesmo corpo, com uma unica peca removida, e ele tem de cair. Foi
  # exatamente este 404 que rodou em producao em toda chamada de abordagem.
  describe 'a prova de que este spec mede a junta, e nao o corpo de hoje' do
    it 'o MESMO corpo sem o `website_token` morre em 404 e nao grava nada' do
      sem_token = exibicao.deep_dup
      sem_token['params'].delete('website_token')
      sem_token['body'].delete('website_token')

      expect { envia(sem_token) }.not_to change(TrackingEvent, :count)
      expect(response).to have_http_status(:not_found)
    end

    it 'a fixture realmente carrega o sentinela — senao o 404 acima passaria por vacuo' do
      # Se o cliente parasse de mandar o token, a fixture perderia o sentinela, a substituicao
      # nao teria o que trocar e o exemplo negativo acima ficaria verde sem medir nada. Esta
      # assercao e o que separa «o token esta la» de «nunca esteve».
      expect(fixture['requests']).to be_present
      expect(fixture['requests']).to all(satisfy { |r| r['params'].to_json.include?(sentinela) || r['body'].to_json.include?(sentinela) })
    end
  end

  # O aceite em uma frase, agora percorrido de ponta a ponta pelo corpo real.
  describe 'a consulta que o bloco existe para tornar possivel' do
    it 'responde exibicoes e conversoes por nivel a partir do que o navegador enviou' do
      envia(exibicao)
      envia(conversao)

      nivel = exibicao.dig('body', 'approach')
      por_nivel = TrackingEvent.where(account_id: account.id)
                               .group("properties->>'approach'", :name).count

      expect(por_nivel[[nivel, 'chatspx_approach_shown']]).to eq(1)
      expect(por_nivel[[nivel, 'chatspx_approach_converted']]).to eq(1)
    end
  end
end
