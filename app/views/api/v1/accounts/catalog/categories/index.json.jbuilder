json.array! @categorias do |categoria|
  json.partial! 'category', categoria: categoria
end
