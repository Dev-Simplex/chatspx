# A tela mostra o titulo e o autor a partir daqui: quem decide o alcance e o backend.
json.meta do
  json.all_account @all_account
end

json.payload do
  json.array! @suggestions, partial: 'api/v1/accounts/suggestions/suggestion', as: :suggestion
end
