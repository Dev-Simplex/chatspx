json.id resource.id
json.name resource.name
json.description resource.description
json.thumbnail resource.avatar_url
json.outgoing_url resource.outgoing_url unless resource.system_bot?
json.bot_type resource.bot_type
json.bot_config resource.bot_config
json.account_id resource.account_id
json.access_token resource.access_token if resource.access_token.present?
# Bloco 4.13 — o segredo com que o POST do bot e assinado. `has_secret` diz que existe,
# sem dizer qual, e vai em toda listagem; o VALOR so sai onde o chamador pede
# (`expose_secret`), que e a criacao e a rotacao — os dois unicos momentos em que o
# cliente precisa copia-lo. Bot de sistema (conta nula) nao tem dono para receber nada.
json.has_secret resource.secret.present? unless resource.system_bot?
json.secret resource.secret if !resource.system_bot? && defined?(expose_secret) && expose_secret
json.system_bot resource.system_bot?
