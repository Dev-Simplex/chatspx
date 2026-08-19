json.id webhook.id
json.name webhook.name
json.url webhook.url
json.account_id webhook.account_id
json.subscriptions webhook.subscriptions
# Bloco 4.14: o segredo NAO volta mais aqui. Este partial serve o index, que lista todos
# os webhooks da conta — devolver segredo em texto claro numa listagem e entrega-lo a
# qualquer tela, log de proxy ou aba aberta. `has_secret` diz a tela que existe um segredo,
# sem dizer qual; o valor so aparece na criacao e na rotacao, uma vez.
json.has_secret webhook.secret.present?
json.secret webhook.secret if defined?(expose_secret) && expose_secret
if webhook.inbox
  json.inbox do
    json.id webhook.inbox.id
    json.name webhook.inbox.name
  end
end
