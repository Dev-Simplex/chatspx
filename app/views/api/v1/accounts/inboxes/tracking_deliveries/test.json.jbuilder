# O retorno do botao de teste tem de ser VISIVEL (T4.7): a mesma forma de uma entrega da
# lista, para que a tela possa empilhar o resultado no topo sem tratar caso especial.
json.delivery do
  json.partial! 'api/v1/accounts/inboxes/tracking_deliveries/tracking_delivery', delivery: @delivery
end
