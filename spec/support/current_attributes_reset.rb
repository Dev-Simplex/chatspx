# `ActiveSupport::CurrentAttributes` e resetado pelo executor do Rails a cada requisicao e a
# cada job. Entre EXEMPLOS de RSpec nao reseta ninguem -- e a thread e a mesma. Entao codigo
# de producao que legitimamente seta `Current` e conta com esse ciclo de vida vaza para o
# exemplo seguinte:
#
#   app/models/message.rb:499                 Current.executed_by = sender  (sem limpar)
#   app/services/automation_rules/action_service.rb:6  Current.executed_by = rule
#
# O sintoma nao parece contaminacao: parece teste instavel. `assignment_history_service_spec`
# passava isolado e falhava no lote gravando `source: "automation"` com `assigned_by_id: nil`
# -- porque `Conversations::AssignmentHistoryService#classify` da prioridade a
# `Current.executed_by` sobre `Current.user`, e o `executed_by` era lixo de outro exemplo.
#
# Resetar ANTES de cada exemplo (e nao so depois) e o que fecha o buraco: hooks `after` de um
# arquivo protegem os outros dele, mas nao protegem ele dos outros -- e nao rodam se o exemplo
# anterior estourou no meio. Hooks de `config` rodam antes dos hooks do proprio arquivo, entao
# um `before { Current.user = actor }` de spec continua valendo normalmente.
RSpec.configure do |config|
  config.before { Current.reset }
end
