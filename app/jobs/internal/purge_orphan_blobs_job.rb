# frozen_string_literal: true

class Internal::PurgeOrphanBlobsJob < ApplicationJob
  queue_as :housekeeping

  # Purge ActiveStorage blobs that are not attached to any record
  # and are older than 7 days (to avoid deleting blobs mid-upload).
  #
  # IMPORTANTE: imagens coladas no editor de ARTIGOS (help center) viram blobs "soltos" —
  # a URL /rails/active_storage/blobs/redirect/<signed_id>/ vai pro `content`, mas nao cria
  # ActiveStorage::Attachment. Sem a exclusao abaixo, o purge apagava essas imagens (registro
  # + arquivo) 7 dias depois, quebrando os artigos (404). Ver #referenced_blob_ids.
  def perform(batch_size: 500)
    protected_ids = referenced_blob_ids

    orphan_blobs = ActiveStorage::Blob.where.not(
      id: ActiveStorage::Attachment.select(:blob_id)
    ).where('active_storage_blobs.created_at < ?', 7.days.ago)
    orphan_blobs = orphan_blobs.where.not(id: protected_ids) if protected_ids.present?

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

  # Blobs referenciados no conteudo de artigos do help center. As imagens sao embutidas por
  # URL (/rails/active_storage/blobs/redirect|proxy/<signed_id>/<nome>), sem attachment — entao
  # decodificamos o signed_id de volta pro blob_id pra proteger esses blobs do purge de orfaos.
  def referenced_blob_ids
    ids = []
    Article.where('content LIKE ?', '%active_storage/blobs%').find_each do |article|
      article.content.to_s.scan(%r{/rails/active_storage/blobs/(?:redirect|proxy)/([^/]+)/}) do |match|
        blob_id = ActiveStorage.verifier.verified(match[0], purpose: :blob_id)
        ids << blob_id if blob_id
      rescue StandardError
        next
      end
    end
    ids.uniq.compact
  end

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
