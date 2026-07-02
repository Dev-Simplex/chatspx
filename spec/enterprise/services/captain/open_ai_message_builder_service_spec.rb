require 'rails_helper'

RSpec.describe Captain::OpenAiMessageBuilderService do
  subject(:service) { described_class.new(message: message) }

  let(:message) { create(:message, content: 'Hello world') }

  describe '#generate_content' do
    context 'when message has only text content' do
      it 'returns the text content directly' do
        expect(service.generate_content).to eq('Hello world')
      end
    end

    context 'when message has no content and no attachments' do
      let(:message) { create(:message, content: nil) }

      it 'returns default message' do
        expect(service.generate_content).to eq('Message without content')
      end
    end

    context 'when message has text content and attachments' do
      before do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :image, external_url: 'https://example.com/image.jpg')
        attachment.save!
      end

      it 'returns an array of content parts' do
        result = service.generate_content
        expect(result).to be_an(Array)
        expect(result).to include({ type: 'text', text: 'Hello world' })
        expect(result).to include({ type: 'image_url', image_url: { url: 'https://example.com/image.jpg' } })
      end
    end

    context 'when message has only non-text attachments' do
      let(:message) { create(:message, content: nil) }

      before do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :image, external_url: 'https://example.com/image.jpg')
        attachment.save!
      end

      it 'returns an array of content parts without text' do
        result = service.generate_content
        expect(result).to be_an(Array)
        expect(result).to include({ type: 'image_url', image_url: { url: 'https://example.com/image.jpg' } })
        expect(result).not_to include(hash_including(type: 'text', text: 'Hello world'))
      end
    end
  end

  describe '#attachment_parts' do
    let(:message) { create(:message, content: nil) }
    let(:attachments) { message.attachments }

    context 'with image attachments' do
      before do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :image, external_url: 'https://example.com/image.jpg')
        attachment.save!
      end

      it 'includes image parts' do
        result = service.send(:attachment_parts, attachments)
        expect(result).to include({ type: 'image_url', image_url: { url: 'https://example.com/image.jpg' } })
      end
    end

    context 'with audio attachments (already transcribed)' do
      let(:audio_attachment) do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :audio)
        attachment.save!
        attachment.update!(meta: { transcribed_text: 'Audio transcription text' })
        attachment
      end

      it 'includes the cached transcription text part' do
        audio_attachment # trigger creation
        result = service.send(:attachment_parts, attachments)
        expect(result).to include({ type: 'text', text: 'Audio transcription text' })
      end
    end

    context 'with other file types' do
      before do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :file)
        attachment.save!
      end

      it 'includes generic attachment message' do
        result = service.send(:attachment_parts, attachments)
        expect(result).to include({ type: 'text', text: 'User has shared an attachment' })
      end
    end

    context 'with mixed attachment types' do
      let(:image_attachment) do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :image, external_url: 'https://example.com/image.jpg')
        attachment.save!
        attachment
      end

      let(:audio_attachment) do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :audio)
        attachment.save!
        attachment.update!(meta: { transcribed_text: 'Audio text' })
        attachment
      end

      let(:document_attachment) do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :file)
        attachment.save!
        attachment
      end

      it 'includes all relevant parts' do
        image_attachment    # trigger creation
        audio_attachment    # trigger creation
        document_attachment # trigger creation

        result = service.send(:attachment_parts, attachments)
        expect(result).to include({ type: 'image_url', image_url: { url: 'https://example.com/image.jpg' } })
        expect(result).to include({ type: 'text', text: 'Audio text' })
        expect(result).to include({ type: 'text', text: 'User has shared an attachment' })
      end
    end
  end

  describe '#image_parts' do
    let(:message) { create(:message, content: nil) }

    context 'with valid image attachments' do
      let(:image1) do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :image, external_url: 'https://example.com/image1.jpg')
        attachment.save!
        attachment
      end

      let(:image2) do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :image, external_url: 'https://example.com/image2.jpg')
        attachment.save!
        attachment
      end

      it 'returns image parts for all valid images' do
        image1 # trigger creation
        image2 # trigger creation

        image_attachments = message.attachments.where(file_type: :image)
        result = service.send(:image_parts, image_attachments)

        expect(result).to include({ type: 'image_url', image_url: { url: 'https://example.com/image1.jpg' } })
        expect(result).to include({ type: 'image_url', image_url: { url: 'https://example.com/image2.jpg' } })
      end
    end

    context 'with image attachments without URLs' do
      let(:image_attachment) do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :image, external_url: nil)
        attachment.save!
        attachment
      end

      before do
        allow(image_attachment).to receive(:file).and_return(instance_double(ActiveStorage::Attached::One, attached?: false))
      end

      it 'skips images without valid URLs' do
        image_attachment # trigger creation

        image_attachments = message.attachments.where(file_type: :image)
        result = service.send(:image_parts, image_attachments)

        expect(result).to be_empty
      end
    end
  end

  describe '#get_attachment_url' do
    let(:attachment) do
      attachment = message.attachments.build(account_id: message.account_id, file_type: :image)
      attachment.save!
      attachment
    end

    context 'when attachment has external_url' do
      before { attachment.update(external_url: 'https://example.com/image.jpg') }

      it 'returns external_url' do
        expect(service.send(:get_attachment_url, attachment)).to eq('https://example.com/image.jpg')
      end
    end

    context 'when attachment has attached file' do
      before do
        attachment.update(external_url: nil)
        allow(attachment).to receive(:file).and_return(instance_double(ActiveStorage::Attached::One, attached?: true))
        allow(attachment).to receive(:file_url).and_return('https://local.com/file.jpg')
        allow(attachment).to receive(:download_url).and_return('')
      end

      it 'returns file_url' do
        expect(service.send(:get_attachment_url, attachment)).to eq('https://local.com/file.jpg')
      end
    end

    context 'when attachment has no URL or file' do
      before do
        attachment.update(external_url: nil)
        allow(attachment).to receive(:file).and_return(instance_double(ActiveStorage::Attached::One, attached?: false))
      end

      it 'returns nil' do
        expect(service.send(:get_attachment_url, attachment)).to be_nil
      end
    end
  end

  describe '#extract_audio_transcriptions' do
    let(:message) { create(:message, content: nil) }

    context 'with no audio attachments' do
      it 'returns empty string' do
        result = service.send(:extract_audio_transcriptions, message.attachments)
        expect(result).to eq('')
      end
    end

    context 'with audio already transcribed (cached)' do
      let(:audio1) do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :audio)
        attachment.save!
        attachment.update!(meta: { transcribed_text: 'First audio text. ' })
        attachment
      end

      let(:audio2) do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :audio)
        attachment.save!
        attachment.update!(meta: { transcribed_text: 'Second audio text.' })
        attachment
      end

      before { allow(Messages::AudioTranscriptionService).to receive(:new) }

      it 'concatenates all cached transcriptions without hitting the API' do
        audio1 # trigger creation
        audio2 # trigger creation

        attachments = message.attachments
        result = service.send(:extract_audio_transcriptions, attachments)
        expect(result).to eq('First audio text. Second audio text.')
        expect(Messages::AudioTranscriptionService).not_to have_received(:new)
      end
    end

    context 'with audio that has no transcription yet' do
      let(:audio_attachment) do
        attachment = message.attachments.build(account_id: message.account_id, file_type: :audio)
        attachment.save!
        attachment
      end

      before do
        allow(Messages::AudioTranscriptionJob).to receive(:perform_later)
        allow(Messages::AudioTranscriptionService).to receive(:new)
      end

      it 'returns a placeholder and enqueues async transcription (never blocks the response)' do
        audio_attachment # trigger creation

        attachments = message.attachments
        result = service.send(:extract_audio_transcriptions, attachments)

        expect(result).to eq('[áudio]')
        expect(Messages::AudioTranscriptionJob).to have_received(:perform_later).with(audio_attachment.id).at_least(:once)
        expect(Messages::AudioTranscriptionService).not_to have_received(:new)
      end
    end
  end

  describe 'private helper methods' do
    describe '#text_part' do
      it 'returns correct text part format' do
        result = service.send(:text_part, 'Hello world')
        expect(result).to eq({ type: 'text', text: 'Hello world' })
      end
    end

    describe '#image_part' do
      it 'returns correct image part format' do
        result = service.send(:image_part, 'https://example.com/image.jpg')
        expect(result).to eq({ type: 'image_url', image_url: { url: 'https://example.com/image.jpg' } })
      end
    end
  end
end
