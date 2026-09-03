json.payload do
  json.webhook do
    # Na criacao o segredo aparece UMA vez: e o unico momento em que o cliente pode copia-lo.
    json.partial! 'webhook', webhook: @webhook, expose_secret: true
  end
end
