class ActiveAttendancePolicy < ApplicationPolicy
  # Espelha ContactPolicy#index?: a aba "Em atendimento" é o mesmo grau de
  # exposição da aba "Todos os contatos" — metadado da conta, sem conteúdo de
  # mensagem. Ver o comentário do escopo em ActiveAttendancesController.
  def index?
    true
  end
end
