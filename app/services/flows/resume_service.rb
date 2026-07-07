# frozen_string_literal: true

# Retoma UM FlowRun suspenso: reentra no Flows::RunnerService no nó que o wait apontou e
# caminha até o grafo acabar ou outro wait suspender de novo. Reentrante — `with_lock` + uma
# re-checagem de status/wait_until DENTRO do lock impedem que dois ticks do ResumeJob retomem
# o mesmo run em duplicidade (espelha o MessageSequences::AdvanceService). Best-effort: um erro
# é logado e o run marcado `failed` (runs-veneno param de tentar) pra um run ruim não derrubar
# o lote. A retomada roda em modo automação (actor nil → autor = sistema, anti-loop por
# flow_id): passado o wait, o disparo humano original já não está "ativo"; ver TODO no plano.
class Flows::ResumeService
  def initialize(flow_run:)
    @flow_run = flow_run
  end

  def perform
    @flow_run.with_lock do
      next unless @flow_run.waiting?
      next if @flow_run.wait_until.nil? || @flow_run.wait_until > Time.current

      Flows::RunnerService.new(
        flow: @flow_run.flow,
        conversation: @flow_run.conversation,
        trigger_payload: @flow_run.context,
        flow_run: @flow_run
      ).resume_from(@flow_run.current_node_id)
    end
  rescue StandardError => e
    Rails.logger.error("Flows::ResumeService flow_run=#{@flow_run&.id}: #{e.message}")
    mark_failed
    nil
  end

  private

  # Não deixa um run-veneno preso em :waiting martelando a cada minuto. O fail! tem seu
  # próprio rescue: se a falha original foi de banco, marcar failed também pode falhar.
  def mark_failed
    @flow_run&.fail!
  rescue StandardError
    nil
  end
end
