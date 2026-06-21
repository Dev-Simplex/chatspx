require 'zip'

# Gera o .zip de um AttachmentBulkDownload em STREAMING para um Tempfile no disco
# (RNF1): nunca monta o zip inteiro em RAM. Cada blob é aberto via blob.open
# (tempfile local) e copiado em chunks com IO.copy_stream direto no OutputStream.
# Modo STORED (sem compressão): mídia já é comprimida (JPEG/MP4); o zip é só
# "envelope" (padrão Google/Dropbox).
class Attachments::BulkDownloadZipService
  Result = Struct.new(:file_size, :processed_count, :skipped_count, :total_bytes, keyword_init: true)

  INVALID_FILENAME_CHARS = %r{[/\\:*?"<>|\x00-\x1f]}

  def initialize(bulk_download)
    @bulk = bulk_download
    @processed = 0
    @skipped = []
    @total_bytes = 0
    @cap_omitted = 0
    @cap_reached = false
    @used_names = Hash.new(0)
  end

  def call
    tempfile = Tempfile.new(['attachment_bulk_download', '.zip'])

    Zip::OutputStream.open(tempfile.path) do |zos|
      download_scope.find_each(batch_size: 25) { |attachment| append_attachment(zos, attachment) }
      zos.put_next_entry('_manifest.txt')
      zos.write(manifest_text)
    end

    attach_zip(tempfile)
    log_cap_reached if @cap_reached
    Result.new(file_size: File.size(tempfile.path), processed_count: @processed,
               skipped_count: @skipped.size + @cap_omitted, total_bytes: @total_bytes)
  ensure
    tempfile&.close
    tempfile&.unlink
  end

  private

  def append_attachment(zos, attachment)
    entry = unique_entry_name(attachment)

    unless attachment.file.attached?
      @skipped << [attachment.id, entry, 'sem arquivo armazenado']
      return
    end

    blob_size = attachment.file.blob.byte_size.to_i

    # Teto de bytes revalidado NA EXECUÇÃO (§T2): no modo filtros/select_all o
    # conjunto pode crescer entre o pedido e o job. Ao estourar MAX_TOTAL_BYTES
    # paramos de adicionar (mantendo ao menos o 1º arquivo) e finalizamos o zip
    # com o que já entrou — sem explodir o job.
    if cap_exceeded?(blob_size)
      @cap_reached = true
      @cap_omitted += 1
      return
    end

    zos.put_next_entry(entry, nil, nil, Zip::Entry::STORED)
    attachment.file.blob.open { |blob_file| IO.copy_stream(blob_file, zos) }
    @total_bytes += blob_size
    @processed += 1
    bump_progress if (@processed % 10).zero?
  rescue StandardError => e
    # 1 arquivo corrompido/IO não mata o lote (§8).
    @skipped << [attachment.id, entry, e.class.name]
  end

  # true quando adicionar este blob ultrapassaria o teto — desde que já tenhamos
  # ao menos 1 arquivo (um único arquivo > teto ainda entra, p/ não gerar zip
  # vazio; o create já barra total > 2GB no caminho normal).
  def cap_exceeded?(blob_size)
    return true if @cap_reached
    return false if @processed.zero?

    @total_bytes + blob_size > AttachmentBulkDownload::MAX_TOTAL_BYTES
  end

  # Re-resolve o escopo a partir do record (mesma regra de visibilidade do
  # controller) e materializa os IDs uma vez; depois itera com preload de blob.
  # Hard cap defensivo de MAX_FILES (§T2): o conjunto de filtros pode ter
  # crescido desde a validação do create — o job nunca processa além do teto.
  def download_scope
    ids = resolver.attachment_ids
    Attachment.where(id: ids)
              .includes(file_attachment: :blob, message: :conversation)
              .limit(AttachmentBulkDownload::MAX_FILES)
  end

  def resolver
    @resolver ||= Attachments::BulkDownloadScopeResolver.new(
      account: @bulk.account,
      user: @bulk.requester_user,
      conversation_id: @bulk.conversation_id,
      attachment_ids: @bulk.params['attachment_ids'],
      filters: @bulk.params['filters']
    )
  end

  def attach_zip(tempfile)
    # bloco fecha o file descriptor após o upload síncrono (record persistido) —
    # evita FD leak que derruba o worker após muitos jobs.
    File.open(tempfile.path) do |file|
      @bulk.file.attach(io: file, filename: zip_filename, content_type: 'application/zip')
    end
  end

  def zip_filename
    ts = Time.current.strftime('%Y%m%d_%H%M%S')
    if @bulk.conversation_id.present?
      "conversa_#{@bulk.conversation&.display_id || @bulk.conversation_id}_midias_#{ts}.zip"
    else
      "midias_#{@bulk.account_id}_#{ts}.zip"
    end
  end

  # conversa-{display_id}/{YYYY-MM-DD_HHMMSS}_{filename_sanitizado}
  # sem conversa associada -> pasta "outros/"; colisão -> sufixo " (1)", " (2)"...
  def unique_entry_name(attachment)
    conversation = attachment.message&.conversation
    folder = conversation ? "conversa-#{conversation.display_id}" : 'outros'
    timestamp = attachment.created_at.strftime('%Y-%m-%d_%H%M%S')
    name = "#{folder}/#{timestamp}_#{sanitize_filename(attachment)}"

    count = @used_names[name]
    @used_names[name] = count + 1
    return name if count.zero?

    ext = File.extname(name)
    "#{name[0...(name.length - ext.length)]} (#{count})#{ext}"
  end

  def sanitize_filename(attachment)
    raw = attachment.file.attached? ? attachment.file.filename.to_s : "arquivo-#{attachment.id}"
    cleaned = raw.gsub(INVALID_FILENAME_CHARS, '_').strip
    cleaned.presence || "arquivo-#{attachment.id}"
  end

  def bump_progress
    # rubocop:disable Rails/SkipsModelValidations
    @bulk.update_columns(processed_count: @processed, updated_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def log_cap_reached
    Rails.logger.warn(
      "[bulk_download] teto de tamanho atingido id=#{@bulk.id} account=#{@bulk.account_id} " \
      "requester=#{@bulk.requester_user_id} processed=#{@processed} omitted=#{@cap_omitted} " \
      "bytes=#{@total_bytes} cap=#{AttachmentBulkDownload::MAX_TOTAL_BYTES}"
    )
  end

  def manifest_text
    lines = [
      'Download em massa de mídias — ChatSPX',
      "Gerado em: #{Time.current.iso8601}",
      "Solicitante: #{@bulk.audit_meta['requester_name'] || @bulk.requester_user_id}",
      "Arquivos incluídos: #{@processed}",
      "Arquivos pulados: #{@skipped.size + @cap_omitted}",
      ''
    ]
    if @cap_reached
      cap_gb = (AttachmentBulkDownload::MAX_TOTAL_BYTES / 1.gigabyte.to_f).round(1)
      lines << "Limite de tamanho atingido (#{cap_gb} GB): #{@cap_omitted} item(ns) omitido(s)."
      lines << ''
    end
    unless @skipped.empty?
      lines << 'PULADOS (não incluídos no ZIP):'
      @skipped.each { |id, name, reason| lines << "- ##{id} #{name} — #{reason}" }
    end
    lines.join("\n")
  end
end
