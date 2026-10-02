require 'rails_helper'

RSpec.describe Attachment, type: :model do
  let(:account) { create(:account, audio_transcriptions: true) }
  let(:conversation) { create(:conversation, account: account) }
  let(:incoming) { create(:message, conversation: conversation, account: account, message_type: :incoming) }

  before do
    allow(AudioTranscriptionJob).to receive(:perform_later)
    allow(Messages::AudioTranscriptionJob).to receive(:perform_later)
  end

  def create_audio
    incoming.attachments.create!(account: account, file_type: :audio, external_url: 'https://example.com/a.ogg')
  end

  def captain_can_transcribe(value)
    allow(Messages::AudioTranscriptionService).to receive(:new)
      .and_return(instance_double(Messages::AudioTranscriptionService, can_transcribe?: value))
  end

  describe 'dono da transcricao de audio' do
    it 'enqueues only the Captain pipeline when the Captain transcribes (um Whisper por audio)' do
      captain_can_transcribe(true)

      attachment = create_audio

      expect(Messages::AudioTranscriptionJob).to have_received(:perform_later).with(attachment.id).once
      expect(AudioTranscriptionJob).not_to have_received(:perform_later)
    end

    it 'falls back to the OSS pipeline when the Captain cannot transcribe' do
      captain_can_transcribe(false)

      attachment = create_audio

      expect(AudioTranscriptionJob).to have_received(:perform_later).with(attachment.id).once
      expect(Messages::AudioTranscriptionJob).not_to have_received(:perform_later)
    end

    it 'falls back to the OSS pipeline when the installation has no Captain key' do
      allow(Messages::AudioTranscriptionService).to receive(:new).and_raise('Failed to initialize OpenAI client')

      attachment = create_audio

      expect(AudioTranscriptionJob).to have_received(:perform_later).with(attachment.id).once
      expect(Messages::AudioTranscriptionJob).not_to have_received(:perform_later)
    end
  end
end
