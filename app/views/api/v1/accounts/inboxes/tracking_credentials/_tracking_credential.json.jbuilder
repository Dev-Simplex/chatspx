json.id resource.id
json.inbox_id resource.inbox_id

# O UNICO caminho pelo qual um campo de segredo aparece numa resposta. O laco varre
# SECRET_ATTRIBUTES em vez de listar os campos a mao: segredo novo no modelo ja sai mascarado aqui,
# e nao ha como acrescentar um campo e esquecer de mascara-lo — que e como o segredo vaza.
TrackingCredential::SECRET_ATTRIBUTES.each do |attribute|
  json.set! attribute, resource.secret_summary(attribute)
end

# Nao e segredo (nao cifra, nao mascara): e o codigo de teste da Meta, que o operador precisa
# reler para conferir contra o painel de Test Events.
json.meta_test_event_code resource.meta_test_event_code
json.oauth_metadata resource.oauth_metadata
json.last_verified_at resource.last_verified_at
