class Captain::Behavior::MediaPipelineService
  def initialize(assistant:, message:)
    @assistant = assistant
    @message = message
    @config = assistant.behavior['media_pipeline'] || {}
  end

  def process
    return nil unless enabled?

    transcribe_audio || ''
  end

  private

  def enabled?
    @config['audio_transcription'] || @config['image_description']
  end

  def transcribe_audio
    return unless @config['audio_transcription']

    audio_attachment = @message.attachments.find { |a| a.file_type == 'audio' }
    return unless audio_attachment

    Messages::AudioTranscriptionService.new(message: @message).process
  end
end
