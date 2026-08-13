require 'rails_helper'

RSpec.describe Attachment, type: :model do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:incoming) { create(:message, conversation: conversation, account: account, message_type: :incoming) }

  before { allow(Captain::MediaDescriptionJob).to receive(:perform_later) }

  def build_image(message: incoming, file_type: :image)
    message.attachments.create!(account: account, file_type: file_type, external_url: 'https://example.com/i.jpg')
  end

  describe 'agendamento da descricao de midia' do
    context 'when no assistant of the account opted in' do
      it 'does not enqueue anything (conta que nao liga nada nao muda de comportamento)' do
        create(:captain_assistant, account: account)

        build_image

        expect(Captain::MediaDescriptionJob).not_to have_received(:perform_later)
      end
    end

    context 'when an assistant of the account opted in' do
      before do
        create(:captain_assistant, account: account, behavior: { 'media_pipeline' => { 'image_description' => true } })
      end

      it 'enqueues the description for an incoming image' do
        attachment = build_image

        expect(Captain::MediaDescriptionJob).to have_received(:perform_later).with(attachment.id)
      end

      it 'ignores outgoing messages' do
        outgoing = create(:message, conversation: conversation, account: account, message_type: :outgoing)

        build_image(message: outgoing)

        expect(Captain::MediaDescriptionJob).not_to have_received(:perform_later)
      end

      it 'ignores file types the layer does not handle yet' do
        build_image(file_type: :video)

        expect(Captain::MediaDescriptionJob).not_to have_received(:perform_later)
      end

      it 'does not let a scheduling failure break the attachment' do
        allow(Captain::Behavior::MediaPipelineService).to receive(:image_description_enabled_for?).and_raise(StandardError, 'boom')

        expect { build_image }.not_to raise_error
      end
    end
  end
end
