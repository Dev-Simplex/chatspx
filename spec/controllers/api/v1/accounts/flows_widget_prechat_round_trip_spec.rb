# frozen_string_literal: true

require 'rails_helper'

# 4.02 — O CANVAS NAO PODE APAGAR O GATILHO DE CAPTURA.
#
# `flows.trigger_config` e uma coluna jsonb com DOIS autores: a SEGMENTACAO da captura
# (`url_conditions`, `priority`, `inbox_ids`, `experiment`…) e escrita por quem edita o alvo, e a
# `definition` (nodes+edges) e escrita pelo CANVAS. O canvas nao edita segmentacao, entao ele manda
# `trigger_config: {}` — e o controller copia o jsonb CRU do cliente
# (`flows_controller.rb#assign_jsonb_attributes`). Substituicao crua + dois autores = perda
# silenciosa: abrir e salvar um fluxo de captura apagava o alvo inteiro, com 200 e sem aviso.
#
# A REGRA que este spec fixa: QUEM NAO DECLARA A CHAVE NAO APAGA A CHAVE. Declarar continua
# mandando — `url_conditions: []` esvazia de verdade; o que nao apaga e a AUSENCIA.
#
# Tudo aqui atravessa o controller e o serializador REAIS (`type: :request`), e o veredito final
# nao e a forma do hash: e o `Flows::WidgetPrechatResolver` continuar entregando o fluxo para a
# mesma URL DEPOIS do save do canvas.
RSpec.describe 'Round-trip do gatilho widget_prechat (4.02)', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }

  # A segmentacao completa de um fluxo de captura de verdade: as quatro chaves que o diagnostico
  # mediu sendo apagadas (`url_conditions`, `priority`, `inbox_ids`, `experiment`) mais o resto do
  # contrato de Flow::WidgetPrechatSchema.
  let(:segmentacao) do
    {
      'url_conditions' => [{ 'operator' => 'contains', 'value' => '/precos' }],
      'match' => 'all',
      'priority' => 7,
      'inbox_ids' => [inbox.id],
      'devices' => ['desktop'],
      'business_hours_only' => false,
      'utm' => { 'utm_source' => 'google' },
      'experiment' => { 'key' => 'captura-2026', 'weight' => 50 }
    }
  end

  let(:flow) do
    create(:flow, account: account, trigger_type: :widget_prechat, trigger_config: segmentacao,
                  definition: {
                    'nodes' => [
                      { 'id' => 'trg', 'type' => 'trigger' },
                      { 'id' => 'n1', 'type' => 'action', 'action_name' => 'send_message',
                        'action_params' => ['Quer um orcamento?'] }
                    ],
                    'edges' => [{ 'from' => 'trg', 'to' => 'n1' }]
                  })
  end

  # A inbox declara que o pre-chat dela e um fluxo (o modo que a tela 3.14 grava) — sem isso o
  # resolver nao entrega fluxo nenhum e o teste de comportamento mediria a guarda, nao o round-trip.
  before do
    web_widget.update!(pre_chat_form_enabled: true,
                       pre_chat_form_options: web_widget.pre_chat_form_options.merge('mode' => 'flow'))
    # `flow` e `let` (preguicoso) e os exemplos que medem ENTREGA chamam o resolver antes de
    # mencionar o fluxo — sem esta linha o resolver rodaria numa conta sem fluxo nenhum e o
    # vermelho seria do spec, nao do defeito.
    flow
  end

  def salvar(payload)
    patch "/api/v1/accounts/#{account.id}/flows/#{flow.id}",
          params: payload, headers: administrator.create_new_auth_token, as: :json
  end

  # LIDO DO BANCO, nao do objeto em memoria: a armadilha desta base e um UPDATE de jsonb que vira
  # no-op silencioso e ainda responde "1 linha afetada". `jsonb_exists` responde sobre a CHAVE,
  # entao distingue "gravou null" de "a chave sumiu".
  def chave_no_banco?(key)
    Flow.connection.select_value(
      Flow.sanitize_sql_array(['SELECT jsonb_exists(trigger_config, ?) FROM flows WHERE id = ?', key, flow.id])
    )
  end

  def config_no_banco
    Flow.find(flow.id).trigger_config
  end

  # O que o resolver entrega para um visitante vindo de uma URL, com a segmentacao como esta AGORA
  # no banco. E o unico veredito que importa: forma de hash certa e fluxo nao entregue seria um
  # verde inutil.
  def fluxo_entregue_para(url)
    Flows::WidgetPrechatResolver.new(
      account: account.reload, inbox: inbox, url: url,
      browser: { 'device_name' => 'Macintosh', 'platform_name' => 'macOS' }
    ).perform
  end

  describe 'o payload que o canvas grava' do
    # O MESMO objeto que `buildTriggerPayload` monta no front — o espelho deste literal esta em
    # `canvas/specs/triggerPayload.spec.js` ("o payload que o rspec do 4.02 recebe"). Os dois lados
    # tem de mudar juntos: e por isso que os dois specs carregam o literal inteiro.
    let(:payload_do_canvas) do
      {
        name: flow.name,
        definition: {
          'nodes' => [
            { 'id' => 'trg', 'type' => 'trigger', 'trigger_kind' => 'widget_prechat' },
            { 'id' => 'n1', 'type' => 'action', 'action_name' => 'send_message',
              'action_params' => ['Quer um orcamento? Temos 3 planos.'] }
          ],
          'edges' => [{ 'from' => 'trg', 'to' => 'n1' }]
        },
        trigger_type: 'widget_prechat',
        trigger_config: segmentacao
      }
    end

    it 'devolve o fluxo AINDA como captura, com a segmentacao intacta no banco' do
      salvar(payload_do_canvas)

      expect(response).to have_http_status(:success)
      expect(Flow.find(flow.id).trigger_type).to eq('widget_prechat')
      expect(config_no_banco).to include(segmentacao)
      expect(chave_no_banco?('url_conditions')).to be(true)
      expect(chave_no_banco?('experiment')).to be(true)
    end

    it 'continua entregando o fluxo para a mesma URL depois do save' do
      expect(fluxo_entregue_para('https://site.com.br/precos?utm_source=google')).to eq(flow)

      salvar(payload_do_canvas)

      expect(fluxo_entregue_para('https://site.com.br/precos?utm_source=google')).to eq(flow)
      # E a edicao do canvas chegou: o round-trip preserva o alvo SEM congelar o desenho.
      expect(Flow.find(flow.id).definition['nodes'].last['action_params']).to eq(['Quer um orcamento? Temos 3 planos.'])
    end
  end

  describe 'um cliente que nao declara a segmentacao' do
    # Exatamente o que o canvas mandava antes deste bloco (FlowCanvasView.vue:681-728 caia no
    # default `{ trigger_type: 'manual', trigger_config: {} }`). O `trigger_type` e uma decisao
    # declarada do cliente e continua valendo; o alvo, que ele NAO declarou, nao pode ser apagado
    # por omissao.
    it 'nao apaga o alvo ao mandar trigger_config vazio' do
      salvar({ name: flow.name, definition: flow.definition, trigger_type: 'manual', trigger_config: {} })

      expect(response).to have_http_status(:success)
      expect(config_no_banco).to include(segmentacao)
      expect(chave_no_banco?('url_conditions')).to be(true)
      expect(chave_no_banco?('priority')).to be(true)
      expect(chave_no_banco?('inbox_ids')).to be(true)
      expect(chave_no_banco?('experiment')).to be(true)
    end

    it 'nao apaga o alvo quando o cliente nem manda a chave trigger_config' do
      salvar({ name: 'Renomeado pelo canvas', definition: flow.definition })

      expect(config_no_banco).to include(segmentacao)
      expect(Flow.find(flow.id).name).to eq('Renomeado pelo canvas')
    end
  end

  # CONTROLE POSITIVO — sem isto o merge poderia ser "nunca muda nada", que passaria os exemplos
  # acima sendo um defeito pior: a tela de segmentacao deixaria de poder apagar uma condicao.
  describe 'quem DECLARA a chave manda nela' do
    it 'esvazia url_conditions quando o cliente manda [] de proposito' do
      salvar({ trigger_type: 'widget_prechat', trigger_config: { 'url_conditions' => [], 'priority' => 7 } })

      expect(response).to have_http_status(:success)
      expect(config_no_banco['url_conditions']).to eq([])
      expect(chave_no_banco?('url_conditions')).to be(true)
      # AS DUAS METADES, medidas por COMPORTAMENTO e no mesmo exemplo:
      # 1. a condicao de URL sumiu de verdade — uma URL que o alvo antigo excluia passa a casar;
      expect(fluxo_entregue_para('https://site.com.br/blog?utm_source=google')).to eq(flow)
      # 2. e o `utm`, que o cliente NAO declarou, continua filtrando. Sem esta linha o exemplo
      #    passaria igual se a preservacao tivesse apagado tudo junto com a condicao de URL.
      expect(fluxo_entregue_para('https://site.com.br/blog')).to be_nil
    end

    it 'troca o valor de uma chave declarada e preserva as que ficaram de fora' do
      salvar({ trigger_type: 'widget_prechat', trigger_config: { 'priority' => -3 } })

      config = config_no_banco
      expect(config['priority']).to eq(-3)
      expect(config['url_conditions']).to eq(segmentacao['url_conditions'])
      expect(config['experiment']).to eq(segmentacao['experiment'])
    end

    it 'desliga o experimento quando a tela manda experiment: null' do
      salvar({ trigger_type: 'widget_prechat', trigger_config: { 'experiment' => nil } })

      expect(config_no_banco['experiment']).to be_nil
      expect(chave_no_banco?('experiment')).to be(true)
      expect(config_no_banco['url_conditions']).to eq(segmentacao['url_conditions'])
    end
  end

  # A ARMADILHA NOMEADA: dois autores gravando a MESMA coluna. Testar um lado so nao prova nada —
  # a perda silenciosa acontece justamente na alternancia.
  describe 'os dois autores gravando, alternadamente' do
    it 'preserva o que cada lado escreveu, em qualquer ordem' do
      # 1. o autor da segmentacao aperta o alvo
      salvar({ trigger_type: 'widget_prechat',
               trigger_config: { 'url_conditions' => [{ 'operator' => 'starts_with', 'value' => 'https://loja.' }],
                                 'priority' => 9 } })

      # 2. o canvas salva o desenho (sem opinar sobre alvo)
      salvar({ definition: { 'nodes' => [{ 'id' => 'trg', 'type' => 'trigger', 'trigger_kind' => 'widget_prechat' },
                                         { 'id' => 'n2', 'type' => 'action', 'action_name' => 'add_label',
                                           'action_params' => ['lead'] }],
                             'edges' => [] },
               trigger_type: 'widget_prechat', trigger_config: {} })

      # 3. o autor da segmentacao volta e mexe SO na prioridade
      salvar({ trigger_type: 'widget_prechat', trigger_config: { 'priority' => 2 } })

      config = config_no_banco
      expect(config['url_conditions']).to eq([{ 'operator' => 'starts_with', 'value' => 'https://loja.' }])
      expect(config['priority']).to eq(2)
      expect(config['experiment']).to eq(segmentacao['experiment'])
      expect(Flow.find(flow.id).definition['nodes'].pluck('id')).to eq(%w[trg n2])
      # o `utm` do alvo original nunca foi declarado por nenhum dos tres saves e continua valendo
      expect(fluxo_entregue_para('https://loja.com.br/carrinho?utm_source=google')).to eq(flow)
    end
  end

  # O outro autor legitimo da MESMA coluna: `webhook_token` ja e backend-autoritativo
  # (Flow#ensure_webhook_token). Este exemplo existe para provar que os dois merges convivem —
  # a preservacao do alvo nao pode atrapalhar a geracao do token, e vice-versa.
  #
  # O que este exemplo NAO afirma: que o `webhook_token` sobreviva a volta. Medido nesta base, ele
  # NAO sobrevive quando o cliente reescreve `trigger_config` (ver a nota em
  # Flow#ensure_webhook_token). E divida do gatilho `external_webhook`, nao do 4.02, e este spec
  # nao a fixa como esperada para nao travar quem for consertar.
  describe 'convivencia com o webhook_token' do
    it 'preserva o alvo de captura mesmo quando o fluxo vira webhook e volta' do
      salvar({ trigger_type: 'external_webhook', trigger_config: {} })
      expect(Flow.find(flow.id).trigger_config['webhook_token']).to be_present
      expect(config_no_banco['url_conditions']).to eq(segmentacao['url_conditions'])

      salvar({ trigger_type: 'widget_prechat', trigger_config: {} })

      expect(Flow.find(flow.id).trigger_type).to eq('widget_prechat')
      expect(config_no_banco).to include(segmentacao)
      expect(fluxo_entregue_para('https://site.com.br/precos?utm_source=google')).to eq(flow)
    end
  end

  # O fluxo que NUNCA foi captura nao ganha alvo nenhum por causa desta regra.
  describe 'fluxos que nao sao captura' do
    let(:manual) { create(:flow, account: account, trigger_type: :manual, trigger_config: { 'a' => 1 }) }

    it 'continua substituindo o trigger_config cru' do
      patch "/api/v1/accounts/#{account.id}/flows/#{manual.id}",
            params: { trigger_type: 'manual', trigger_config: {} },
            headers: administrator.create_new_auth_token, as: :json

      expect(Flow.find(manual.id).trigger_config).to eq({})
    end
  end
end
