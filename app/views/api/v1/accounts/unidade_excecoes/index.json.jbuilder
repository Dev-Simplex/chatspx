json.array! @excecoes do |unidade_excecao|
  json.partial! 'unidade_excecao', unidade_excecao: unidade_excecao
end
