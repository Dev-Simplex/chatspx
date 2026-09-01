require 'rails_helper'

# Bloco 5.05 — o CONTRATO PUBLICO do endpoint, cruzado com o que o servidor realmente responde.
#
# `swagger/swagger.json` nao e documentacao de gaveta: e o arquivo servido em
# `GET /swagger/swagger.json` (ver `spec/controllers/swagger_controller_spec.rb`) e a fonte que o
# integrador le antes de escrever a primeira linha. Ele prometia `204 No Content` muito depois de o
# endpoint passar a responder `200 { event_id, name, properties }` — e prometer corpo vazio faz o
# cliente jogar fora justamente o `event_id` que a deduplicacao da Meta exige.
#
# Por isso os exemplos abaixo nao leem so o JSON: eles fazem a REQUISICAO e comparam. Um spec que
# so olhasse o arquivo ficaria verde com o codigo divergindo — que e exatamente o defeito que esta
# onda existe para nao repetir.
RSpec.describe 'swagger — contrato publico de POST /api/v1/widget/events', type: :request do
  let(:documento) { JSON.parse(Rails.root.join('swagger/swagger.json').read) }
  let(:operacao) { documento.dig('paths', '/api/v1/widget/events', 'post') }

  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: inbox.id }).generate_token
  end

  def post_event(params)
    post '/api/v1/widget/events',
         params: { website_token: web_widget.website_token }.merge(params),
         headers: { 'X-Auth-Token' => token },
         as: :json
  end

  it 'documenta 200 e nao 204 — e o servidor responde o que esta documentado' do
    post_event(name: 'webwidget.triggered')

    expect(operacao['responses'].keys).to include('200')
    expect(operacao['responses'].keys).not_to include('204')
    expect(response.code).to eq('200')
  end

  it 'documenta o 422, que o endpoint responde de verdade para nome fora do contrato' do
    post_event(name: 'conversation.resolved')

    expect(operacao['responses'].keys).to include('422')
    expect(response.code).to eq('422')
    expect(operacao.dig('responses', '422', 'content', 'application/json', 'schema')).to be_present
  end

  # A assercao forte: as chaves que o esquema do 200 declara sao EXATAMENTE as que a resposta traz.
  # Declarar de menos manda o integrador ignorar o `event_id`; declarar de mais o manda esperar
  # campo que nunca chega.
  it 'o esquema do 200 e a resposta real tem as MESMAS chaves' do
    post_event(name: 'webwidget.triggered', event_info: { referer: 'https://loja.exemplo.com/planos' })

    referencia = operacao.dig('responses', '200', 'content', 'application/json', 'schema', '$ref')
    esquema = documento.dig('components', 'schemas', referencia.to_s.split('/').last)

    expect(esquema['properties'].keys).to match_array(response.parsed_body.keys)
    expect(esquema['properties'].keys).to include('event_id', 'name', 'properties')
  end

  it 'a descricao nao promete mais corpo vazio' do
    expect(operacao['description']).not_to include('204')
    expect(operacao['description']).to include('event_id')
  end

  # O corpo aceito pelo endpoint tambem e contrato: `properties` e `event_key` sao a porta do
  # `track()` do site (5.16) e nao estavam documentados em lugar nenhum.
  it 'documenta o corpo que o endpoint realmente aceita, incluindo o track() do site' do
    referencia = operacao.dig('requestBody', 'content', 'application/json', 'schema', '$ref')
    esquema = documento.dig('components', 'schemas', referencia.to_s.split('/').last)

    expect(esquema['properties'].keys).to include('name', 'event_info', 'properties', 'event_key')
  end

  # A ARMADILHA CONHECIDA desta base, e o unico jeito de ela nao voltar em silencio: `rake
  # swagger:build` regenera o arquivo a partir de `swagger/paths/`, que NAO tem as rotas do widget —
  # rodar a tarefa hoje derruba o documento de 353 caminhos para 89 e ninguem percebe, porque
  # nenhum teste olhava para o tamanho. O piso e o que existe no commit deste bloco; acrescentar
  # endpoint passa, PERDER endpoint reprova.
  it 'nao perdeu caminhos: o documento servido continua completo' do
    expect(documento['paths'].size).to be >= 353
    expect(documento['paths']).to have_key('/api/v1/widget/events')
  end
end
