# frozen_string_literal: true

# Guarda do walker: o que fazer quando o laco do Flows::RunnerService#walk termina de forma ANOMALA.
# Estourar MAX_STEPS e ciclo no grafo, nao conclusao - antes caia no #finish_run e o run virava
# `completed`, o que alem da rajada de mensagens DESARMAVA a espera: a Flows::ReplyResumeService nao
# achava mais run `waiting` e a resposta seguinte do cliente era descartada em silencio.
# Extraido p/ manter o RunnerService enxuto (mesmo padrao de Flows::StepInstrumentation, ReplyWait e
# SimulationWalk). Depende do host: as ivars @dry_run/@flow/@conversation/@flow_run e a constante
# MAX_STEPS - resolvida via self.class:: porque constante em modulo e LEXICAL, nao herdada do incluidor.
module Flows::WalkGuard
  private

  def fail_on_step_limit
    return if @dry_run

    Rails.logger.error("Flows::RunnerService flow=#{@flow&.id} conversation=#{@conversation&.id} " \
                       "run=#{@flow_run&.id}: MAX_STEPS (#{self.class::MAX_STEPS}) excedido - ciclo no grafo?")
    @flow_run&.fail!
  end
end
