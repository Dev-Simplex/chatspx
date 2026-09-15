require 'rails_helper'

RSpec.describe Messages::AudioTranscriptionService, type: :service do
  let(:account) { create(:account, audio_transcriptions: true) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, conversation: conversation) }
  let(:attachment) { message.attachments.create!(account: account, file_type: :audio) }

  before do
    # Create required installation configs
    InstallationConfig.find_or_create_by!(name: 'CAPTAIN_OPEN_AI_API_KEY') { |config| config.value = 'test-api-key' }
    InstallationConfig.find_or_create_by!(name: 'CAPTAIN_OPEN_AI_MODEL') { |config| config.value = 'gpt-4o-mini' }

    # Mock usage limits for transcription to be available
    allow(account).to receive(:usage_limits).and_return({ captain: { responses: { current_available: 100 } } })
  end

  describe '#perform' do
    let(:service) { described_class.new(attachment) }

    context 'when captain_integration feature is not enabled' do
      before do
        account.disable_features!('captain_integration')
      end

      it 'returns transcription limit exceeded' do
        expect(service.perform).to eq({ error: 'Transcription limit exceeded' })
      end
    end

    context 'when transcription is successful' do
      before do
        # Mock can_transcribe? to return true and transcribe_audio method
        allow(service).to receive(:can_transcribe?).and_return(true)
        allow(service).to receive(:transcribe_audio).and_return('Hello world transcription')
      end

      it 'returns successful transcription' do
        result = service.perform
        expect(result).to eq({ success: true, transcriptions: 'Hello world transcription' })
      end
    end

    context 'when audio transcriptions are disabled' do
      before do
        account.update!(audio_transcriptions: false)
      end

      it 'returns error for transcription limit exceeded' do
        result = service.perform
        expect(result).to eq({ error: 'Transcription limit exceeded' })
      end
    end

    context 'when attachment already has transcribed text' do
      before do
        attachment.update!(meta: { transcribed_text: 'Existing transcription' })
        allow(service).to receive(:can_transcribe?).and_return(true)
      end

      it 'returns existing transcription without calling API' do
        result = service.perform
        expect(result).to eq({ success: true, transcriptions: 'Existing transcription' })
      end
    end
  end

  describe '#fetch_audio_file' do
    let(:service) { described_class.new(attachment) }

    before do
      attachment.file.attach(
        io: File.open(Rails.public_path.join('audio/widget/ding.mp3')),
        filename: 'speech',
        content_type: 'audio/mpeg'
      )
    end

    it 'adds extension from content type when filename has no extension' do
      temp_file_path = service.send(:fetch_audio_file)

      expect(File.extname(temp_file_path)).to eq('.mpeg')
    ensure
      FileUtils.rm_f(temp_file_path) if temp_file_path.present?
    end

    # O mesmo anexo e enfileirado por dois pontos (hook de criacao do anexo e builder de
    # historico do Captain). Com nome deterministico, os dois jobs usavam o MESMO caminho.
    it 'usa um caminho diferente a cada execucao' do
      primeiro = service.send(:fetch_audio_file)
      segundo = described_class.new(attachment).send(:fetch_audio_file)

      expect(primeiro).not_to eq(segundo)
      expect(File.extname(primeiro)).to eq(File.extname(segundo))
    ensure
      FileUtils.rm_f(primeiro) if primeiro.present?
      FileUtils.rm_f(segundo) if segundo.present?
    end

    it 'nao apaga o arquivo temporario de outro job no mesmo anexo' do
      # Job A ja baixou o audio e esta com o arquivo aberto no whisper.
      caminho_do_job_a = described_class.new(attachment).send(:fetch_audio_file)

      # Job B roda o ciclo inteiro, incluindo o `ensure` que apaga o proprio temporario.
      allow(service).to receive_messages(whisper_with_retry: 'transcrito', update_transcription: nil)
      service.send(:transcribe_audio)

      expect(File).to exist(caminho_do_job_a)
    ensure
      FileUtils.rm_f(caminho_do_job_a) if caminho_do_job_a.present?
    end
  end
end
