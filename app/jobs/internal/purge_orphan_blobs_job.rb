# frozen_string_literal: true

class Internal::PurgeOrphanBlobsJob < ApplicationJob
  queue_as :housekeeping

  # Purge ActiveStorage blobs that are not attached to any record
  # and are older than 7 days (to avoid deleting blobs mid-upload)
  def perform(batch_size: 500)
    orphan_blobs = ActiveStorage::Blob.where.not(
      id: ActiveStorage::Attachment.select(:blob_id)
    ).where('active_storage_blobs.created_at < ?', 7.days.ago)

    total = orphan_blobs.count
    purged = 0

    Rails.logger.info("[PurgeOrphanBlobsJob] Found #{total} orphan blobs to purge")

    orphan_blobs.find_each(batch_size: batch_size) do |blob|
      blob.purge
      purged += 1
    rescue StandardError => e
      Rails.logger.warn("[PurgeOrphanBlobsJob] Failed to purge blob #{blob.id}: #{e.message}")
    end

    # Clean empty directories
    clean_empty_directories

    Rails.logger.info("[PurgeOrphanBlobsJob] Purged #{purged}/#{total} orphan blobs")
  end

  private

  def clean_empty_directories
    storage_path = Rails.root.join('storage')
    return unless Dir.exist?(storage_path)

    Dir.glob("#{storage_path}/**/").sort_by(&:length).reverse_each do |dir|
      next if dir == "#{storage_path}/"

      Dir.rmdir(dir) if Dir.empty?(dir)
    rescue Errno::ENOTEMPTY, Errno::ENOENT
      # Directory not empty or already deleted
    end
  end
end
