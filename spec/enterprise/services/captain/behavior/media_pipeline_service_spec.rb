require 'rails_helper'

RSpec.describe Captain::Behavior::MediaPipelineService, type: :service do
  let(:account) { create(:account) }
  let(:assistant) do
    create(:captain_assistant, account: account, behavior: { 'media_pipeline' => { 'audio_transcription' => true } })
  end
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, conversation: conversation, account: account) }
  let!(:audio_attachment) { message.attachments.create!(account: account, file_type: :audio) }

  describe '#process' do
    # O caminho vive desligado por padrao, entao nenhum monitor pega uma chamada errada aqui:
    # o double VERIFICADO (verify_partial_doubles) e quem garante que a assinatura bate com o
    # servico de verdade — anexo posicional e `perform`, nao `message:` e `process`.
    it 'chama o servico de transcricao com o anexo posicional e devolve o texto' do
      transcricao = instance_double(Messages::AudioTranscriptionService,
                                    perform: { success: true, transcriptions: 'alo, bom dia' })
      expect(Messages::AudioTranscriptionService).to receive(:new).with(audio_attachment).and_return(transcricao)

      resultado = described_class.new(assistant: assistant, message: message).process

      expect(resultado).to eq('alo, bom dia')
    end

    it 'devolve string vazia quando a transcricao falha' do
      transcricao = instance_double(Messages::AudioTranscriptionService, perform: { error: 'OpenAI request failed' })
      allow(Messages::AudioTranscriptionService).to receive(:new).and_return(transcricao)

      resultado = described_class.new(assistant: assistant, message: message).process

      expect(resultado).to eq('')
    end

    it 'nao chama o servico quando a chave esta desligada' do
      assistant.update!(behavior: { 'media_pipeline' => { 'audio_transcription' => false } })
      expect(Messages::AudioTranscriptionService).not_to receive(:new)

      expect(described_class.new(assistant: assistant, message: message).process).to be_nil
    end
  end
end
