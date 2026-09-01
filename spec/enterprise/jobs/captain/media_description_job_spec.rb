require 'rails_helper'

# As duas metades do vídeo são independentes: descrever os quadros (o que está ESCRITO na
# tela) e transcrever o áudio (o que é FALADO). Foram separadas porque o proveito muda por
# cliente — medido no story da Tozi, os quadros trazem código e preço enquanto o Whisper
# devolve "Music Plays" e uma fila de emoji. Quem liga uma não pode pagar pela outra.
RSpec.describe Captain::MediaDescriptionJob do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:message) { create(:message, account: account) }
  let(:service) { instance_double(Captain::MediaDescriptionService, perform: nil, transcribe: nil) }

  let(:video) do
    att = message.attachments.build(account_id: account.id, file_type: :ig_story,
                                    external_url: 'https://cdn.example.com/story.mp4')
    att.save!
    att
  end

  before do
    allow(Captain::MediaDescriptionService).to receive(:new).and_return(service)
    allow(Captain::MediaDescriptionService).to receive(:video?).and_return(true)
  end

  context 'when only the description key is on' do
    before { assistant.update!(behavior: { 'media_pipeline' => { 'video_description' => true } }) }

    it 'describes the frames and does not transcribe' do
      described_class.perform_now(video.id)

      expect(service).to have_received(:perform)
      expect(service).not_to have_received(:transcribe)
    end
  end

  context 'when only the transcription key is on' do
    before { assistant.update!(behavior: { 'media_pipeline' => { 'video_transcription' => true } }) }

    it 'transcribes and does not describe' do
      described_class.perform_now(video.id)

      expect(service).to have_received(:transcribe)
      expect(service).not_to have_received(:perform)
    end
  end

  context 'when the account opted out of both' do
    it 'does neither' do
      described_class.perform_now(video.id)

      expect(service).not_to have_received(:perform)
      expect(service).not_to have_received(:transcribe)
    end
  end

  # Imagem não passa pelo gate de vídeo: quem já checou a política foi o hook do anexo, e
  # mudar isso desligaria a descrição de imagem que já está em produção.
  context 'when the attachment is not a video' do
    it 'keeps the image path untouched' do
      allow(Captain::MediaDescriptionService).to receive(:video?).and_return(false)

      described_class.perform_now(video.id)

      expect(service).to have_received(:perform)
      expect(service).not_to have_received(:transcribe)
    end
  end
end
