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

  SCHEMA = {
    'type' => 'object',
    'properties' => {
      'meta_pixel_id' => { 'type' => 'string', 'pattern' => META_PIXEL_ID_PATTERN },
      'ga4_measurement_id' => { 'type' => 'string', 'pattern' => GA4_MEASUREMENT_ID_PATTERN },
      'google_ads_send_to' => { 'type' => 'string', 'pattern' => GOOGLE_ADS_SEND_TO_PATTERN },
      'event_map' => {
        'type' => 'object',
        'maxProperties' => MAX_EVENT_MAP_ENTRIES,
        'additionalProperties' => { 'type' => 'string', 'minLength' => 1, 'maxLength' => MAX_EVENT_NAME_LENGTH }
      },
      'consent_mode' => { 'type' => 'string', 'enum' => CONSENT_MODES },
      'test_mode' => { 'type' => 'boolean' }
    },
    'additionalProperties' => false
  }.freeze
end
