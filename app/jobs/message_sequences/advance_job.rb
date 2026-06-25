# frozen_string_literal: true

# Drives the drip: every minute (config/schedule.yml) it picks up enrollments whose
# next step is due and advances each one. Per-enrollment rescue lives in
# AdvanceService, so one failure never stops the batch.
class MessageSequences::AdvanceJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    MessageSequenceEnrollment.due.find_each do |enrollment|
      MessageSequences::AdvanceService.new(enrollment: enrollment).perform
    end
  end
end
