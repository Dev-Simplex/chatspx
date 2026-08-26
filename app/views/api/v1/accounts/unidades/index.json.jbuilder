json.unidades @unidades do |unidade|
  json.id unidade.id
  json.slug unidade.slug
  json.nome unidade.nome
  json.cidade unidade.cidade
  json.uf unidade.uf
  json.ativa unidade.ativa
  json.endereco unidade.endereco
  json.telefone unidade.telefone
  json.timezone unidade.timezone
  json.etiquetas unidade.etiquetas_normalizadas
  json.atributos unidade.atributos

  # A grade sai na ordem em que se lê no Brasil (segunda a domingo), não na ordem numérica do
  # `wday`. Os rótulos ficam no i18n do front — aqui vai o número do dia.
  json.grade Spx::Unidade::ORDEM_LEITURA do |dia|
    json.dia_semana dia
    # `cadastrado: false` é "não sei", e é DIFERENTE de fechada. Quem cadastrou só os dias úteis
    # tem sábado desconhecido, não sábado fechado — e a tela precisa poder dizer isso, senão
    # devolve invenção com cara de dado.
    json.cadastrado unidade.dia_cadastrado?(dia)
    json.faixas unidade.faixas_padrao(dia).map(&:to_s)
  end
end

json.etiquetas @etiquetas
