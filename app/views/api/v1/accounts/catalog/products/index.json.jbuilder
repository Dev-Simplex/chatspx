json.payload do
  json.array! @produtos do |produto|
    json.partial! 'product', produto: produto
  end
end
json.meta do
  json.total @total
  json.page @pagina
  # Conta sem espelho configurado: a aba esconde selos e botões de sincronizar.
  json.meta_sync_enabled meta_sync_enabled?
  json.per_page Api::V1::Accounts::Catalog::ProductsController::RESULTADOS_POR_PAGINA
end
