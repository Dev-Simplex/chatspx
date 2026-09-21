json.payload do
  json.array! @produtos do |produto|
    json.partial! 'api/v1/accounts/catalog/products/product', produto: produto
  end
end
json.meta do
  json.total @total
  json.page @pagina
  json.per_page @por_pagina
end
