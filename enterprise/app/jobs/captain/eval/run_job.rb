# Roda o conjunto de casos fora da request (bloco 6.02). O clique do cliente devolve a
# execução PENDENTE na hora; a tela acompanha o status.
class Captain::Eval::RunJob < ApplicationJob
  queue_as :low

  def perform(run)
    return if run.blank? || run.status == 'concluida'

    Captain::Eval::RunService.new(assistant: run.captain_assistant).executar(run)
  end
end
