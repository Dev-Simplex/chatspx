# A projecao PUBLICA de `widget_tracking` (bloco 3.04, regra dura do plano 24 §15.1).
#
# O que sai para o widget e uma PROJECAO por lista branca, nunca o objeto inteiro do banco. A razao
# nao e teorica: `widget_tracking` e publicado no HTML de toda pagina do site do cliente, e a lista
# negativa de 3.01 barra a ESCRITA de segredo — mas um segredo gravado por outro caminho (console,
# import, migration de terceiro, bug futuro) sairia junto se a leitura fosse `to_json` do hash.
#
# Identificador publico e publico de verdade: Pixel ID e Measurement ID aparecem no HTML de qualquer
# site que use as tags. Ja o access token da Meta permite ESCREVER eventos em nome do cliente — esse
# mora em tabela propria com `encrypts`, atras do pre-requisito de chaves (blocos 0.10 e 5.02).
module WidgetTrackingProjection
  PUBLIC_KEYS = %w[
    meta_pixel_id
    ga4_measurement_id
    google_ads_send_to
    event_map
    install_tags
    consent_mode
    test_mode
    lead_value
  ].freeze

  module_function

  def public_view(tracking)
    return {} unless tracking.is_a?(Hash)

    tracking.slice(*PUBLIC_KEYS)
  end
end
