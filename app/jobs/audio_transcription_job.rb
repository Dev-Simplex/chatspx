class AudioTranscriptionJob < ApplicationJob
  queue_as :low

  def perform(attachment_id, language: 'pt')
    attachment = Attachment.find_by(id: attachment_id)
    return if attachment.blank?

    AudioTranscriptionService.new(
      attachment: attachment,
      language: language,
      account: attachment.account
    ).perform
  end
end
