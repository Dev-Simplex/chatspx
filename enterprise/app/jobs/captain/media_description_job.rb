class Captain::MediaDescriptionJob < ApplicationJob
  queue_as :low

  # O anexo pode ainda nao ter subido pro storage quando o commit dispara o job.
  retry_on ActiveStorage::FileNotFoundError, wait: 2.seconds, attempts: 3

  def perform(attachment_id)
    attachment = Attachment.find_by(id: attachment_id)
    return if attachment.blank?

    Captain::MediaDescriptionService.new(attachment: attachment).perform
  end
end
