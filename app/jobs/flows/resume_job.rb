# frozen_string_literal: true

# Empurra os flows suspensos adiante: a cada minuto (config/schedule.yml) pega os FlowRuns
# cujo wait venceu e retoma cada um. O lock por-run e o rescue vivem no ResumeService, então
# uma falha nunca para o lote. Espelha MessageSequences::AdvanceJob.
class Flows::ResumeJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    FlowRun.due.find_each do |flow_run|
      Flows::ResumeService.new(flow_run: flow_run).perform
    end
  end
end
