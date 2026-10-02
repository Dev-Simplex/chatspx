json.id produto.id
json.name produto.name
json.description produto.description
json.price_cents produto.price_cents
json.promo_price_cents produto.promo_price_cents
json.current_price_cents produto.preco_atual_cents
json.on_sale produto.em_promocao?
json.currency produto.currency
json.sku produto.sku
json.stock produto.stock
json.visible produto.visible
json.featured produto.featured
json.catalog_category_id produto.catalog_category_id
json.category_name produto.category&.name
json.custom_attributes produto.custom_attributes
# Os mesmos campos já no formato de exibição (`[{ label, value }]`), sem os internos: é o que o
# card mostra. Formatar na tela duplicaria a regra que a legenda do WhatsApp já usa.
json.custom_fields campos_personalizados.para_exibir(produto.custom_attributes)
json.source produto.source
json.external_id produto.external_id
json.read_only produto.read_only?
json.meta_product_id produto.meta_product_id
json.meta_synced_at produto.meta_synced_at
# Estado do espelho (sincronizado/pendente/incompleto; nulo para oculto) e o que falta ao incompleto.
json.meta_status produto.meta_status
json.meta_missing produto.faltas_para_meta
# URL assinada, boa para o painel. O espelho da Meta precisa de URL PÚBLICA e estável — é outra
# conversa, e mora na C7/C9 (ver docs/catalogo-whatsapp.md).
json.images produto.imagens_para_api
json.cover_url produto.capa_url
json.created_at produto.created_at
json.updated_at produto.updated_at
