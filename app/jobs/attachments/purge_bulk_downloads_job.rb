# Retenção (RNF3): apaga zips de bulk download vencidos (blob + record) e marca
# como failed exports presos em processing (worker/VM reiniciado no meio).
# Agendado diariamente via sidekiq-cron (config/schedule.yml).
class Attachments::PurgeBulkDownloadsJob < ApplicationJob
  queue_as :housekeeping

  STUCK_THRESHOLD = 2.hours

  def perform
    purge_expired
    fail_stuck
  end

  private

  def purge_expired
    AttachmentBulkDownload.expired.find_each do |bulk|
      bulk.file.purge if bulk.file.attached?
      bulk.destroy
    end
  end

  def fail_stuck
    AttachmentBulkDownload.processing
                          .where(started_at: ..STUCK_THRESHOLD.ago)
                          .find_each do |bulk|
      bulk.update(status: :failed, error_message: 'job interrompido (timeout/restart)', completed_at: Time.current)
    end
  end
end
