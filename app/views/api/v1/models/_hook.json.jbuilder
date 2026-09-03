json.id resource.id
json.app_id resource.app_id
json.status resource.enabled?
json.inbox resource.inbox&.slice(:id, :name)
json.account_id resource.account_id
json.hook_type resource.hook_type

# `settings` guarda a credencial da integracao. Cada app declara em
# `config/integration/apps.yml` quais propriedades podem sair na resposta (`visible_properties`);
# a lista existia para 7 das 13 integracoes e NUNCA era aplicada na leitura — o jsonb inteiro
# voltava, segredo incluso (credentials, app_secret, page_access_token, shared_secret...).
#
# Esta e a terceira peca de um contrato que ja estava no codigo: `EditHook.vue` tem
# `keysServerDidNotReturn` e `HooksController#blanking_a_key_the_client_never_saw?` usa a mesma
# lista para ignorar um vazio vindo do cliente. Sem o filtro, as outras duas nao tinham efeito.
#
# Filtra SOMENTE quando o app declara a lista: os 6 que nao declaram (webhooks, dashboard_apps,
# linear, notion, slack, shopify) seguem exatamente como antes.
if Current.account_user&.administrator?
  visible_properties = Array(resource.app&.visible_properties).map(&:to_s)
  json.settings visible_properties.present? ? resource.settings.to_h.slice(*visible_properties) : resource.settings
end
json.reference_id resource.reference_id if Current.account_user&.administrator?
