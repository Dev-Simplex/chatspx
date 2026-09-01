json.id unidade_excecao.id
json.data_inicio unidade_excecao.data_inicio
json.data_fim unidade_excecao.data_fim
json.fechada unidade_excecao.fechada
json.motivo unidade_excecao.motivo
json.etiqueta unidade_excecao.etiqueta
json.unidade_id unidade_excecao.unidade_id
json.unidade_nome unidade_excecao.unidade&.nome

# A faixa já formatada, para a tela não repetir a aritmética de relógio que o model faz.
# Nula quando a exceção fecha, ou quando ela só diz "abre no horário de sempre".
json.horario unidade_excecao.faixa&.to_s

# 2 = uma unidade · 1 = uma etiqueta · 0 = a conta inteira. É a mesma escala que decide qual
# exceção vence, então a tela mostra o alcance com o número que o motor usa, e não com um
# rótulo paralelo que poderia divergir dele.
json.especificidade unidade_excecao.especificidade
