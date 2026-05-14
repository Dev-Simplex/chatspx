# Audio::WaveformGenerationJob
#
# Runs after an audio attachment is committed. Downloads the audio blob to a
# tempfile, invokes Audio::WaveformExtractor and persists the resulting peak
# array into Attachment#meta['waveform_peaks'] so that the mobile/web client
# can render a precomputed waveform without re-decoding the file.
#
# The job is idempotent: a second run for the same attachment is a no-op as
# long as peaks are already present. Persistence uses update_column to avoid
# re-triggering the after_create_commit callbacks (transcription / waveform).
class Audio::WaveformGenerationJob < ApplicationJob
  queue_as :low

  def perform(attachment_id)
    attachment = Attachment.find_by(id: attachment_id)
    return if attachment.blank?
    return unless attachment.file_type.to_s == 'audio'
    return if attachment.meta&.dig('waveform_peaks').present?

    peaks = extract_peaks(attachment)
    return if peaks.blank?

    persist_peaks(attachment, peaks)
    notify_message_updated(attachment)
  end

  private

  def extract_peaks(attachment)
    with_local_audio_file(attachment) do |path|
      Audio::WaveformExtractor.new(path).extract
    end
  end

  # Yields a local filesystem path to the audio bytes. Cleans up the tempfile
  # afterwards. Returns whatever the block returned, or [] if no source.
  def with_local_audio_file(attachment)
    tempfile = build_tempfile(attachment)
    return [] if tempfile.nil?

    yield(tempfile.path)
  ensure
    cleanup_tempfile(tempfile)
  end

  def build_tempfile(attachment)
    tmp = Tempfile.new(['waveform', tempfile_extension(attachment)], binmode: true)
    written = copy_audio_into(attachment, tmp)

    if written
      tmp.flush
      tmp.rewind
      tmp
    else
      cleanup_tempfile(tmp)
      nil
    end
  rescue StandardError => e
    Rails.logger.warn("[Audio::WaveformGenerationJob] download failed for attachment ##{attachment.id}: #{e.class}: #{e.message}")
    cleanup_tempfile(tmp)
    nil
  end

  def tempfile_extension(attachment)
    ext = attachment.extension.to_s.strip.delete_prefix('.')
    ext.present? ? ".#{ext}" : '.bin'
  end

  def copy_audio_into(attachment, tmp)
    if attachment.file.attached?
      attachment.file.blob.open { |blob_io| IO.copy_stream(blob_io, tmp) }
      true
    elsif attachment.external_url.present?
      tmp.write(Net::HTTP.get(URI.parse(attachment.external_url)).force_encoding('BINARY'))
      true
    else
      false
    end
  end

  def cleanup_tempfile(tmp)
    return if tmp.nil?

    tmp.close unless tmp.closed?
    tmp.unlink
  rescue StandardError
    nil
  end

  def persist_peaks(attachment, peaks)
    new_meta = (attachment.meta || {}).merge('waveform_peaks' => peaks)
    # Skip callbacks: metadata-only update; we do not want to re-enqueue
    # transcription or waveform extraction.
    attachment.update_column(:meta, new_meta) # rubocop:disable Rails/SkipsModelValidations
  end

  def notify_message_updated(attachment)
    message = attachment.message
    return if message.blank?

    Rails.configuration.dispatcher.dispatch(
      ::Events::Types::MESSAGE_UPDATED,
      Time.zone.now,
      message: message.reload,
      performed_by: nil
    )
  rescue StandardError => e
    Rails.logger.warn("[Audio::WaveformGenerationJob] dispatch failed: #{e.class}: #{e.message}")
  end
end
