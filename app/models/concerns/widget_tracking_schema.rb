# Schema de `widget_tracking` (bloco 5.01), validado por `json_schemer` — o mesmo caminho de
# `WidgetTriggersSchema` e `WidgetAppearanceSchema`, e a razao de o plano ter recusado Zod (§10.2 N3):
# validacao de config mora no servidor, porque e o servidor que grava.
#
# POR QUE ESTE SCHEMA E A DEFESA PRINCIPAL, e nao a lista negativa de nomes:
# `widget_tracking` e publicado no HTML de toda pagina do site do cliente. Segredo que entra ali
# fica publico para sempre — cache, historico do navegador, view-source. Lista negativa recusa o que
# alguem lembrou de listar; `additionalProperties: false` recusa TUDO que nao foi declarado publico,
# inclusive o nome de segredo que ninguem previu. A lista negativa continua, como segunda camada.
#
# A lista de chaves e a MESMA de `WidgetTrackingProjection::PUBLIC_KEYS`, e ha spec que falha se as
# duas divergirem. Sem isso, uma chave aceita na escrita e descartada na leitura: o cliente salva,
# a tela confirma, e o dado some sem aviso — que e a forma de mentira que esta onda existe para matar.
module WidgetTrackingSchema
  # Identificadores PUBLICOS, cada um com o formato que a plataforma dona dele publica:
  #   meta_pixel_id       digitos             (aparece no HTML de qualquer site com o pixel)
  #   ga4_measurement_id  G-XXXXXXXX
  #   google_ads_send_to  AW-000/RotuloOpcional
  # O que ESCREVE em nome do cliente (access token da Meta, por exemplo) nao mora aqui: mora em
  # tabela propria com `encrypts`, atras dos blocos 0.10 e 5.02.
  #
  # Os padroes checam a FORMA do identificador — nunca o comprimento exato. A diferenca importa:
  # forma errada e sinal de que ali entrou outra coisa (um token tem letras; um Pixel ID nao),
  # enquanto comprimento exato e uma aposta sobre como a plataforma numera os clientes dela. Um
  # minimo inventado de 5 digitos ja teria recusado o `meta_pixel_id` de um teste desta base, e na
  # frota recusaria o cliente que nao fez nada errado — que e o falso positivo que custa mais caro.
  META_PIXEL_ID_PATTERN = '^[0-9]{1,20}$'.freeze
  GA4_MEASUREMENT_ID_PATTERN = '^G-[A-Za-z0-9]{1,20}$'.freeze
  GOOGLE_ADS_SEND_TO_PATTERN = '^AW-[0-9]{1,15}(/[A-Za-z0-9_-]{1,40})?$'.freeze

  # Nomes oficiais do Google Consent Mode v2. `disabled` e o default por ausencia (regra A4:
  # `nil` tem significado e nao ha backfill) — e significa o comportamento de hoje.
  CONSENT_MODES = %w[disabled basic advanced].freeze

  # O mapa de eventos e do cliente: ele nomeia o evento dele. Teto de 50 entradas porque o objeto
  # inteiro viaja no HTML de toda pagina, e o orcamento de bytes do widget e o mesmo que os blocos
  # 1.07/1.08 defenderam derrubando o CSS de 1.692.204 B para 100.717 B.
  MAX_EVENT_MAP_ENTRIES = 50
  MAX_EVENT_NAME_LENGTH = 100

  # T-C4.3 — instalar a tag que FALTA na pagina do cliente. Opt-in, e o default e a AUSENCIA
  # da chave, que le-se como desligado nos dois alvos (decisao Q5: nunca por padrao).
  #
  # POR QUE E UM OBJETO, e nao um booleano so: instalar o pixel da Meta e instalar o gtag do
  # Google sao duas autorizacoes diferentes. O cliente que ja tem GTM no site quer o Google
  # vindo do container DELE e pode querer o pixel da Meta vindo de nos; um booleano unico
  # obrigaria a escolher entre nao receber nada na Meta e deixar-nos injetar um segundo gtag
  # numa pagina que ja tem governanca de tags.
  #
  # E POR QUE ELE TEM `additionalProperties: false` NO NIVEL DELE TAMBEM: a defesa da raiz nao
  # desce sozinha. Sem esta linha, `install_tags` viraria um saco aberto dentro de um objeto
  # que e publicado no HTML de TODA pagina do site do cliente — `{ meta: true, access_token:
  # "EAA…" }` seria gravado, projetado e servido em texto claro. A lista negativa de nomes
  # pegaria `access_token`; nao pegaria o nome de segredo que ninguem previu, que e exatamente
  # o buraco que `additionalProperties: false` fecha.
  INSTALL_TAG_TARGETS = %w[meta google].freeze

  # Modos de valor do lead. Espelham `LEAD_VALUE_MODES` de `widgetTrackingContract.js`.
  LEAD_VALUE_MODES = %w[off fixed by_rule].freeze

  # ── O FORMATO QUE A TELA GRAVA ────────────────────────────────────────────────────────
  #
  # Ate aqui este schema declarava `event_map` como `nome => string`, `test_mode` como
  # booleano, e nao declarava `lead_value`. A Tela 4 (bloco 5.06) grava objeto nos tres. O
  # resultado era 422 em TODO salvamento da tela: o administrador mexia no mapa de eventos,
  # clicava em salvar e nao salvava nada.
  #
  # POR QUE NENHUM TESTE PEGAVA: cada trilha testava o SEU formato. O spec deste arquivo
  # gravava `'event_map' => { 'conversation_started' => 'Lead' }` e passava; o spec da tela
  # montava o objeto e passava. Ninguem rodava o payload da tela contra o validador. O
  # exemplo "a Tela 4 salva" no fim deste spec existe exatamente para fechar esse vao.
  #
  # QUAL FORMATO VENCE, e por que nao foi moeda ao ar: o objeto carrega o que a string nao
  # consegue dizer. `{ enabled: false, meta: nil, ga4: "widget_open" }` e "manda so ao GA4,
  # e com este nome, e desligado por padrao" — tres decisoes que uma string unica apaga. O
  # mesmo vale para `test_mode`: um booleano nao guarda o `test_event_code` da Meta nem o
  # `started_at`, e sem `started_at` o desligamento automatico de 7 dias vira uma frase na
  # tela e nada no dado.
  #
  # A STRING CONTINUA ACEITA, e nao por indecisao: uma inbox pode ja te-la gravada por API, e
  # `sdk/tracking/tags.js` (`entradaDoMapa`) ja le as duas — ela significa "renomeie este
  # evento assim nos dois destinos". Recusa-la agora quebraria quem nao fez nada errado.
  EVENT_MAP_STRING = { 'type' => 'string', 'minLength' => 1, 'maxLength' => MAX_EVENT_NAME_LENGTH }.freeze

  # `meta`/`ga4` aceitam `null` porque `null` E o dado: significa "nao mandar para este
  # destino", que e diferente de "mandar com o nome vazio". Onze das doze entradas de fabrica
  # usam isso em pelo menos um dos destinos.
  EVENT_MAP_DESTINO = {
    'type' => %w[string null], 'minLength' => 1, 'maxLength' => MAX_EVENT_NAME_LENGTH
  }.freeze

  EVENT_MAP_OBJECT = {
    'type' => 'object',
    'properties' => {
      'enabled' => { 'type' => 'boolean' },
      'meta' => EVENT_MAP_DESTINO,
      'ga4' => EVENT_MAP_DESTINO
    },
    'additionalProperties' => false
  }.freeze

  # `code` e o `test_event_code` da Meta — publico no sentido deste schema (nao autoriza
  # nada; so marca o evento como teste), e por isso ele pode morar aqui. `started_at` e o que
  # faz o prazo de 7 dias existir no DADO, e nao so na tela.
  TEST_MODE_OBJECT = {
    'type' => 'object',
    'properties' => {
      'enabled' => { 'type' => 'boolean' },
      'code' => { 'type' => %w[string null], 'maxLength' => 32 },
      'started_at' => { 'type' => %w[string null] }
    },
    'additionalProperties' => false
  }.freeze

  # Sem teto e sem minimo de proposito: a tela nao valida faixa nenhuma, e um limite aqui que
  # ela nao conhece devolveria de novo um 422 que o administrador nao consegue explicar — que
  # e o defeito que este bloco esta consertando.
  LEAD_VALUE_OBJECT = {
    'type' => 'object',
    'properties' => {
      'mode' => { 'type' => 'string', 'enum' => LEAD_VALUE_MODES },
      'amount' => { 'type' => %w[number null] }
    },
    'additionalProperties' => false
  }.freeze

  SCHEMA = {
    'type' => 'object',
    'properties' => {
      'meta_pixel_id' => { 'type' => 'string', 'pattern' => META_PIXEL_ID_PATTERN },
      'ga4_measurement_id' => { 'type' => 'string', 'pattern' => GA4_MEASUREMENT_ID_PATTERN },
      'google_ads_send_to' => { 'type' => 'string', 'pattern' => GOOGLE_ADS_SEND_TO_PATTERN },
      'event_map' => {
        'type' => 'object',
        'maxProperties' => MAX_EVENT_MAP_ENTRIES,
        'additionalProperties' => { 'anyOf' => [EVENT_MAP_STRING, EVENT_MAP_OBJECT] }
      },
      'install_tags' => {
        'type' => 'object',
        'properties' => INSTALL_TAG_TARGETS.index_with { |_alvo| { 'type' => 'boolean' } },
        'additionalProperties' => false
      },
      'consent_mode' => { 'type' => 'string', 'enum' => CONSENT_MODES },
      'test_mode' => { 'anyOf' => [{ 'type' => 'boolean' }, TEST_MODE_OBJECT] },
      'lead_value' => LEAD_VALUE_OBJECT
    },
    'additionalProperties' => false
  }.freeze
end
