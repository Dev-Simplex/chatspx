# SEM envelope `payload` — o front le estas tres chaves na raiz. A razao esta no cabecalho
# do controller: com `payload` a tela nao daria erro, daria uma lista vazia e silenciosa.
json.deliveries do
  json.array! @deliveries, partial: 'api/v1/accounts/inboxes/tracking_deliveries/tracking_delivery', as: :delivery
end
json.retention_days @retention_days
json.kill_switch @kill_switch
