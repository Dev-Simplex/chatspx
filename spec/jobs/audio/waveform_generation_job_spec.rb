require 'rails_helper'

RSpec.describe Audio::WaveformGenerationJob do
  subject(:job) { described_class }

  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, account: account, conversation: conversation) }
  let(:peaks) { Array.new(64) { |i| (i / 63.0).round(4) } }

  let(:audio_attachment) do
    attachment = message.attachments.new(account_id: message.account_id, file_type: :audio)
    attachment.file.attach(
      io: Rails.root.join('spec/assets/sample.mp3').open,
      filename: 'sample.mp3',
      content_type: 'audio/mpeg'
    )
    attachment.save!
    attachment
  end

  before do
    # Prevent side jobs from firing during attachment setup. We invoke the job
    # directly via perform_now in each example, never through perform_later.
    allow(AudioTranscriptionJob).to receive(:perform_later)
    allow(described_class).to receive(:perform_later)
  end

  describe 'queue' do
    it 'is enqueued on the :low queue' do
      expect(job.new.queue_name).to eq('low')
    end
  end

  describe '#perform' do
    context 'when attachment is missing' do
      it 'returns without doing anything' do
        expect(Audio::WaveformExtractor).not_to receive(:new)
        described_class.perform_now(0)
      end
    end

    context 'when attachment is not audio' do
      let(:image_attachment) do
        a = message.attachments.new(account_id: message.account_id, file_type: :image)
        a.file.attach(
          io: Rails.root.join('spec/assets/avatar.png').open,
          filename: 'avatar.png',
          content_type: 'image/png'
        )
        a.save!
        a
      end

      it 'is a no-op' do
        expect(Audio::WaveformExtractor).not_to receive(:new)
        described_class.perform_now(image_attachment.id)
      end
    end

    context 'when peaks were already persisted (idempotency)' do
      before do
        audio_attachment.update_column(:meta, { 'waveform_peaks' => peaks }) # rubocop:disable Rails/SkipsModelValidations
      end

      it 'does not re-run the extractor' do
        expect(Audio::WaveformExtractor).not_to receive(:new)
        described_class.perform_now(audio_attachment.id)
      end

      it 'leaves existing peaks untouched' do
        described_class.perform_now(audio_attachment.id)
        expect(audio_attachment.reload.meta['waveform_peaks']).to eq(peaks)
      end
    end

    context 'when extraction succeeds' do
      let(:extractor) { instance_double(Audio::WaveformExtractor, extract: peaks) }

      before do
        allow(Audio::WaveformExtractor).to receive(:new).and_return(extractor)
      end

      it 'persists peaks into attachment.meta' do
        described_class.perform_now(audio_attachment.id)
        expect(audio_attachment.reload.meta['waveform_peaks']).to eq(peaks)
      end

      it 'preserves pre-existing meta keys' do
        audio_attachment.update_column(:meta, { 'transcribed_text' => 'hello' }) # rubocop:disable Rails/SkipsModelValidations
        described_class.perform_now(audio_attachment.id)
        meta = audio_attachment.reload.meta
        expect(meta['transcribed_text']).to eq('hello')
        expect(meta['waveform_peaks']).to eq(peaks)
      end

      it 'dispatches a MESSAGE_UPDATED event' do
        # `audio_attachment` e preguicoso e cria conta + mensagem — que DISPARAM eventos. Avaliado
        # depois do dublê, o `account.created` do proprio arranjo caia nele e a expectativa
        # estrita falhava apontando um evento que o job nem emitiu. Materializa antes.
        anexo = audio_attachment
        dispatcher = double('dispatcher')
        allow(Rails.configuration).to receive(:dispatcher).and_return(dispatcher)
        expect(dispatcher).to receive(:dispatch).with(
          ::Events::Types::MESSAGE_UPDATED,
          instance_of(ActiveSupport::TimeWithZone),
          hash_including(message: kind_of(Message), performed_by: nil)
        )
        described_class.perform_now(anexo.id)
      end

      it 'is idempotent on a second run' do
        described_class.perform_now(audio_attachment.id)

        # `allow(...)` NAO zera o historico do espiao: `have_received` continuava contando a
        # chamada da PRIMEIRA execucao, entao o exemplo falhava com "received: 1 time" mesmo o
        # codigo estando correto. Uma expectativa negativa vale a partir de AGORA — e e isso que
        # se quer provar: a segunda execucao nao instancia o extrator de novo.
        expect(Audio::WaveformExtractor).not_to receive(:new)

        described_class.perform_now(audio_attachment.id)
        expect(audio_attachment.reload.meta['waveform_peaks']).to eq(peaks)
      end
    end

    context 'when extraction returns an empty array' do
      let(:extractor) { instance_double(Audio::WaveformExtractor, extract: []) }

      before do
        allow(Audio::WaveformExtractor).to receive(:new).and_return(extractor)
      end

      it 'does not persist anything' do
        described_class.perform_now(audio_attachment.id)
        meta = audio_attachment.reload.meta
        expect(meta).to be_nil.or(satisfy { |m| m['waveform_peaks'].blank? })
      end
    end

    context 'when the attachment has no file and no external_url' do
      let(:audio_attachment) do
        message.attachments.create!(account_id: message.account_id, file_type: :audio)
      end

      it 'does not raise and skips extraction' do
        expect(Audio::WaveformExtractor).not_to receive(:new)
        expect { described_class.perform_now(audio_attachment.id) }.not_to raise_error
      end
    end
  end
end
