# Copia o cadastro da tabela `unidades` (aposentada) para `units`, que passou a ser a única.
#
# SQL cru de propósito: os modelos do lado antigo saem neste mesmo PR, e uma task que depende deles
# morre junto. Aqui ela continua rodando depois — inclusive numa VM que ficou para trás.
#
# SECO por padrão. `rake spx:unidades:unificar[executar]` é o que grava.
#
# O que a conversão tem de não-óbvio:
#   * turno partido — a tabela antiga usa DUAS linhas no mesmo dia (07:30-11:30 e 13:30-17:30); a
#     `unit_working_hours` tem índice único por dia e diz o mesmo com `break_*`. Duas linhas viram
#     uma com intervalo. Três ou mais não têm como caber: a task RECUSA o dia e diz qual, em vez de
#     escolher duas e jogar o resto fora calada.
#   * nome duplicado — `units` tem índice único (conta, nome). Se já existe unidade com o nome, a
#     task NÃO sobrescreve: relata e segue. Fundir duas fichas é decisão de gente.
#   * exceção por etiqueta — a antiga permitia regra sem unidade, valendo para toda unidade marcada;
#     `unit_exceptions` é sempre de UMA unidade. Essas a task relata e não converte.
namespace :spx do
  namespace :unidades do
    desc 'Copia unidades -> units (SECO por padrao; passe [executar] para gravar)'
    task :unificar, [:modo] => :environment do |_t, args|
      Spx::UnificarUnidades.new(executar: args[:modo].to_s == 'executar').call
    end
  end
end
