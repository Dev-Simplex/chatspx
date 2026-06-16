# Espelha Conversations::ExportPdfJob: marca processing -> gera o zip -> attach
# -> completed/failed. SEM retry_on explícito (o retry vem do sidekiq.yml,
# max_retries: 5) — mesma decisão do export de PDF. Fila :low.
class Attachments::BulkDownloadJob < ApplicationJob
  queue_as :low

  discard_on ActiveJob::DeserializationError

  def perform(bulk_download_id)
    bulk = AttachmentBulkDownload.find_by(id: bulk_download_id)
    return unless bulk
    return if bulk.completed? # idempotência: retry após sucesso não regenera

    # TOCTOU (§T3): a ConversationPolicy foi checada só no create. Se o agente
    # perdeu acesso à inbox dentro da janela de retenção, fechamos a porta aqui.
    return if authorization_revoked?(bulk)

    bulk.update!(status: :processing, started_at: Time.current)
    result = Attachments::BulkDownloadZipService.new(bulk).call
    finalize(bulk, result)
  rescue ActiveRecord::RecordNotFound => e
    # Conversa/anexo apagado entre o pedido e a execução: erro PERMANENTE.
    # Marca failed e NÃO re-levanta — evita 5 retries inúteis no Sidekiq (§T4).
    mark_failed(bulk, 'registro_nao_encontrado', e)
  rescue StandardError => e
    Rails.logger.error(
      "[bulk_download] erro #{bulk_download_id}: #{e.class} - #{e.message}\n#{e.backtrace.first(8).join("\n")}"
    )
    mark_failed(bulk, "#{e.class}: #{e.message}")
    raise
  end

  private

  # No modo conversa, revalida que a inbox segue visível ao solicitante. Falha
  # terminal (sem retry) quando o acesso foi revogado. Modo galeria já re-resolve
  # a visibilidade no próprio scope, então não precisa de checagem extra.
  def authorization_revoked?(bulk)
    return false if bulk.conversation_id.blank?

    visible_inbox_ids = Attachments::GalleryScopeBuilder.new(
      user: bulk.requester_user, account: bulk.account, filters: {}
    ).visible_inbox_ids
    return false if visible_inbox_ids.include?(bulk.conversation&.inbox_id)

    mark_failed(bulk, 'acesso_revogado')
    true
  end

  def mark_failed(bulk, reason, error = nil)
    return unless bulk

    bulk.file.purge if bulk.file.attached?
    message = error ? "#{reason} (#{error.class})" : reason
    bulk.update(status: :failed, error_message: message.truncate(2000), completed_at: Time.current)
  end

  def finalize(bulk, result)
    if result.processed_count.zero?
      # Tudo pulado (0 baixáveis) -> failed, sem zip órfão (§8).
      bulk.file.purge if bulk.file.attached?
      bulk.update!(status: :failed, error_message: 'nenhum arquivo disponível para download',
                   processed_count: 0, skipped_count: result.skipped_count, completed_at: Time.current)
      return
    end

    bulk.update!(
      status: :completed,
      processed_count: result.processed_count,
      skipped_count: result.skipped_count,
      total_bytes: result.total_bytes,
      file_size: result.file_size,
      completed_at: Time.current
    )
    log_completion(bulk)
  end

  def log_completion(bulk)
    Rails.logger.info(
      "[bulk_download] done id=#{bulk.id} account=#{bulk.account_id} requester=#{bulk.requester_user_id} " \
      "files=#{bulk.processed_count} skipped=#{bulk.skipped_count} bytes=#{bulk.total_bytes} " \
      "duration_ms=#{bulk.duration_ms} ip=#{bulk.audit_meta['ip']} origin=#{bulk.audit_meta['origin']}"
    )
  end
end
