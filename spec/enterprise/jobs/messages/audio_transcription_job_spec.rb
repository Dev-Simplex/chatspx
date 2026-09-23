require 'rails_helper'

RSpec.describe Messages::AudioTranscriptionJob do
  subject(:job) { described_class.perform_later(attachment_id) }

  let(:message) { create(:message) }
  let(:attachment) do
    message.attachments.create!(
      account_id: message.account_id,
      file_type: :audio,
      file: fixture_file_upload('public/audio/widget/ding.mp3')
    )
  end
  let(:attachment_id) { attachment.id }
  let(:conversation) { message.conversation }
  let(:transcription_service) { instance_double(Messages::AudioTranscriptionService) }

  it 'enqueues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .with(attachment_id)
      .on_queue('low')
  end

  context 'when performing the job' do
    before do
      allow(Messages::AudioTranscriptionService).to receive(:new).with(attachment).and_return(transcription_service)
      allow(transcription_service).to receive(:perform)
    end

    it 'calls AudioTranscriptionService with the attachment' do
      expect(Messages::AudioTranscriptionService).to receive(:new).with(attachment)
      expect(transcription_service).to receive(:perform)
      described_class.perform_now(attachment_id)
    end

    context 'when the audio download fails its integrity check' do
      before do
        allow(transcription_service).to receive(:perform).and_raise(ActiveStorage::IntegrityError)
      end

      it 'retries the same attachment after two seconds on the low queue' do
        freeze_time do
          expect { described_class.perform_now(attachment_id) }.to have_enqueued_job(described_class)
            .with(attachment_id)
            .on_queue('low')
            .at(a_value_within(0.3.seconds).of(2.seconds.from_now))
        end
      end

      it 'stops retrying after three failed attempts' do
        transcription_job = described_class.new(attachment_id)
        2.times { transcription_job.perform_now }

        expect { transcription_job.perform_now }.to raise_error do |error|
          expect(error.class.name).to eq('ActiveStorage::IntegrityError')
        end
        expect(transcription_service).to have_received(:perform).exactly(3).times
      end
    end

    it 'does nothing when attachment is not found' do
      expect(Messages::AudioTranscriptionService).not_to receive(:new)
      described_class.perform_now(999_999)
    end
  end
end
