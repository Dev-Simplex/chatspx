class ActiveAttendancePolicy < ApplicationPolicy
  # ATENÇÃO: o controller autoriza com um SÍMBOLO (`authorize(:active_attendance)`)
  # porque não existe model ActiveAttendance. Os métodos herdados da
  # ApplicationPolicy que tocam o record (`show?` faz record.id, `scope` faz
  # record.class) quebrariam com um Symbol. Hoje a rota é `only: [:index]`, então
  # nada mais é alcançável — quem for adicionar ação de membro (Fase 3) precisa
  # definir o método aqui em vez de herdar.
  #
  # index? = true espelha ContactPolicy#index?: a aba "Em atendimento" é o mesmo
  # grau de exposição da aba "Todos os contatos" — metadado da conta, sem conteúdo
  # de mensagem. Ver a justificativa do escopo em ActiveAttendancesController.
  def index?
    true
  end
end
