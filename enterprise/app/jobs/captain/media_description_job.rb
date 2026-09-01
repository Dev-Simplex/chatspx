class Captain::MediaDescriptionJob < ApplicationJob
  queue_as :low

  # O anexo pode ainda nao ter subido pro storage quando o commit dispara o job.
  retry_on ActiveStorage::FileNotFoundError, wait: 2.seconds, attempts: 3

  def perform(attachment_id)
    attachment = Attachment.find_by(id: attachment_id)
    return if attachment.blank?

    service = Captain::MediaDescriptionService.new(attachment: attachment)
    return service.perform unless Captain::MediaDescriptionService.video?(attachment)

    # As duas metades do video sao independentes de proposito: a conta que quer ler o que
    # esta escrito na tela nao paga pela transcricao da trilha, e vice-versa. O hook so
    # sabe que UMA delas esta ligada; qual, e aqui que se decide.
    politica = Captain::Behavior::MediaPipelineService
    account = attachment.account
    service.perform if politica.video_description_enabled_for?(account)
    service.transcribe if politica.video_transcription_enabled_for?(account)
  end
end
