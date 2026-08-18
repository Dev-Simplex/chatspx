require 'rails_helper'

describe Instagram::SendOnInstagramService do
  subject(:send_reply_service) { described_class.new(message: message) }

  let!(:account) { create(:account) }
  let!(:instagram_channel) { create(:channel_instagram, account: account, instagram_id: 'instagram-message-id-123') }
  let!(:instagram_inbox) { create(:inbox, channel: instagram_channel, account: account, greeting_enabled: false) }

  let!(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: instagram_inbox) }
  let(:conversation) { create(:conversation, contact: contact, inbox: instagram_inbox, contact_inbox: contact_inbox) }
  let(:response) { double }
  let(:mock_response) do
    instance_double(
      HTTParty::Response,
      :success? => true,
      :body => { message_id: 'random_message_id' }.to_json,
      :parsed_response => { 'message_id' => 'random_message_id' }
    )
  end

  let(:error_body) do
    {
      'error' => {
        'message' => 'The Instagram account is restricted.',
        'type' => 'OAuthException',
        'code' => 400,
        'fbtrace_id' => 'anyrandomfbtraceid1234567890'
      }
    }
  end

  let(:error_response) do
    instance_double(
      HTTParty::Response,
      :success? => false,
      :body => error_body.to_json,
      :parsed_response => error_body
    )
  end

  let(:response_with_error) do
    instance_double(
      HTTParty::Response,
      :success? => true,
      :body => error_body.to_json,
      :parsed_response => error_body
    )
  end

  describe '#perform' do
    context 'with reply' do
      before do
        allow(HTTParty).to receive(:post).and_return(mock_response)
      end

      context 'without message_tag HUMAN_AGENT' do
        before do
          InstallationConfig.where(name: 'ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT').first_or_create(value: false)
        end

        it 'if message is sent from chatwoot and is outgoing' do
          message = create(:message, message_type: 'outgoing', inbox: instagram_inbox, account: account, conversation: conversation)

          response = described_class.new(message: message).perform
          expect(response['message_id']).to eq('random_message_id')
        end

        # O Instagram aceita até 30 imagens em `message.attachments[]` numa requisição só, e é
        # o que a capacidade do canal declara: duas fotos viram UMA chamada, não duas.
        it 'if message is sent from chatwoot and is outgoing with multiple attachments' do
          message = build(:message, content: nil, message_type: 'outgoing', inbox: instagram_inbox, account: account,
                                    conversation: conversation)
          avatar = message.attachments.new(account_id: message.account_id, file_type: :image)
          avatar.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
          sample = message.attachments.new(account_id: message.account_id, file_type: :image)
          sample.file.attach(io: Rails.root.join('spec/assets/sample.png').open, filename: 'sample.png', content_type: 'image/png')
          message.save!

          service = described_class.new(message: message)

          sent = []
          allow(service).to receive(:send_message) { |params| sent << params }
          service.perform

          expect(sent.size).to eq(1)
          # A URL assinada do Active Storage muda a cada chamada, então o que se afirma é a
          # forma: um payload de imagem por anexo, na ordem, dentro da MESMA requisição.
          expect(sent.first.dig(:message, :attachments).pluck(:type)).to eq(%w[image image])
          expect(sent.first.dig(:message, :attachments).map { |part| part.dig(:payload, :url) })
            .to contain_exactly(a_string_including(avatar.file.filename.to_s), a_string_including(sample.file.filename.to_s))
        end

        # Contraprova da capacidade: com o canal declarando que NÃO agrupa, o mesmo par de
        # fotos volta a sair numa requisição por anexo. (A contraprova de canal real é o
        # Messenger, que herda o mesmo BaseSendService sem a capacidade.)
        it 'sends one request per attachment when the channel does not group images' do
          message = build(:message, content: nil, message_type: 'outgoing', inbox: instagram_inbox, account: account,
                                    conversation: conversation)
          2.times do |i|
            attachment = message.attachments.new(account_id: message.account_id, file_type: :image)
            attachment.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: "avatar-#{i}.png",
                                   content_type: 'image/png')
          end
          message.save!
          allow(instagram_channel).to receive(:supports_multi_image_message?).and_return(false)

          service = described_class.new(message: message)
          allow(service).to receive(:send_message)
          service.perform

          expect(service).to have_received(:send_message).exactly(:twice)
        end

        # Anexo que não é imagem no meio derrubaria a requisição inteira: `attachments[]` só
        # aceita `image`. Nesse caso o envio volta pro caminho de sempre.
        it 'sends one request per attachment when the batch is not made only of images' do
          message = build(:message, content: nil, message_type: 'outgoing', inbox: instagram_inbox, account: account,
                                    conversation: conversation)
          image = message.attachments.new(account_id: message.account_id, file_type: :image)
          image.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
          document = message.attachments.new(account_id: message.account_id, file_type: :file)
          document.file.attach(io: Rails.root.join('spec/assets/sample.pdf').open, filename: 'sample.pdf', content_type: 'application/pdf')
          message.save!

          service = described_class.new(message: message)
          allow(service).to receive(:send_message)
          service.perform

          expect(service).to have_received(:send_message).exactly(:twice)
        end

        # Anexo sem arquivo local (o tool aponta pra URL pública em vez de baixar) mandava
        # `url: ""` — a Meta recusava e ninguém via.
        it 'points the payload at the external url when the attachment has no local file' do
          message = build(:message, content: nil, message_type: 'outgoing', inbox: instagram_inbox, account: account,
                                    conversation: conversation)
          message.attachments.new(account_id: message.account_id, file_type: :image, external_url: 'https://cdn.example.com/1.jpg')
          message.save!

          service = described_class.new(message: message)
          allow(service).to receive(:send_message)
          service.perform

          expect(service).to have_received(:send_message).with(
            hash_including(message: hash_including(attachment: hash_including(payload: { url: 'https://cdn.example.com/1.jpg' })))
          )
        end

        it 'if message with attachment is sent from chatwoot and is outgoing' do
          message = build(:message, message_type: 'outgoing', inbox: instagram_inbox, account: account, conversation: conversation)
          attachment = message.attachments.new(account_id: message.account_id, file_type: :image)
          attachment.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
          message.save!
          response = described_class.new(message: message).perform

          expect(response['message_id']).to eq('random_message_id')
        end

        it 'if message sent from chatwoot is failed' do
          message = create(:message, message_type: 'outgoing', inbox: instagram_inbox, account: account, conversation: conversation)

          allow(HTTParty).to receive(:post).and_return(response_with_error)
          described_class.new(message: message).perform
          expect(HTTParty).to have_received(:post)
          expect(message.reload.status).to eq('failed')
          expect(message.reload.external_error).to eq('400 - The Instagram account is restricted.')
        end
      end

      context 'with message_tag HUMAN_AGENT' do
        before do
          InstallationConfig.where(name: 'ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT').first_or_create(value: true)
        end

        it 'if message is sent from chatwoot and is outgoing' do
          message = create(:message, message_type: 'outgoing', inbox: instagram_inbox, account: account, conversation: conversation)

          allow(HTTParty).to receive(:post).with(
            {
              recipient: { id: contact.get_source_id(instagram_inbox.id) },
              message: {
                text: message.content
              },
              messaging_type: 'MESSAGE_TAG',
              tag: 'HUMAN_AGENT'
            }
          ).and_return(
            {
              'message_id': 'random_message_id'
            }
          )

          described_class.new(message: message).perform
          expect(HTTParty).to have_received(:post)
        end
      end

      # A vitrine é AGNÓSTICA de canal: a mensagem carrega `cards` em content_attributes e
      # cada canal traduz pro formato dele — aqui, generic template.
      context 'with a card showcase' do
        let(:cards) do
          [{ 'title' => 'Casa 3 quartos — Centro', 'subtitle' => 'R$ 1.950/mês', 'image_url' => 'https://cdn.example.com/1.jpg',
             'button' => { 'title' => 'Fotos do 5194', 'payload' => 'imovel:5194' } }]
        end
        let(:message) do
          create(:message, message_type: 'outgoing', inbox: instagram_inbox, account: account, conversation: conversation,
                           content: 'Separei 1 opção pra você', content_attributes: { 'cards' => cards })
        end

        before { InstallationConfig.where(name: 'ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT').first_or_create(value: false) }

        it 'sends a single generic template carrying every card' do
          service = described_class.new(message: message)
          allow(service).to receive(:send_message)
          service.perform

          expect(service).to have_received(:send_message).once
          expect(service).to have_received(:send_message).with(
            hash_including(message: {
                             attachment: {
                               type: 'template',
                               payload: {
                                 template_type: 'generic',
                                 elements: [{
                                   title: 'Casa 3 quartos — Centro',
                                   image_url: 'https://cdn.example.com/1.jpg',
                                   subtitle: 'R$ 1.950/mês',
                                   buttons: [{ type: 'postback', title: 'Fotos do 5194', payload: 'imovel:5194' }]
                                 }]
                               }
                             }
                           })
          )
        end

        # Contraprova: sem a capacidade, a vitrine NÃO sai como card — a mensagem cai no
        # texto do `content`. É o oposto do interactive_payload, que saía vazio sem aviso.
        it 'falls back to the plain text when the channel does not draw cards' do
          allow(instagram_channel).to receive(:supports_card_carousel?).and_return(false)

          service = described_class.new(message: message)
          allow(service).to receive(:send_message)
          service.perform

          expect(service).to have_received(:send_message).with(
            hash_including(message: { text: 'Separei 1 opção pra você' })
          )
        end
      end

      context 'when handling errors' do
        it 'handles HTTP errors' do
          message = create(:message, message_type: 'outgoing', inbox: instagram_inbox, account: account, conversation: conversation)
          allow(HTTParty).to receive(:post).and_return(error_response)

          described_class.new(message: message).perform

          expect(message.reload.status).to eq('failed')
          expect(message.reload.external_error).to eq('400 - The Instagram account is restricted.')
        end

        it 'handles response errors' do
          message = create(:message, message_type: 'outgoing', inbox: instagram_inbox, account: account, conversation: conversation)

          error_response = instance_double(
            HTTParty::Response,
            success?: true,
            body: { 'error' => { 'message' => 'Invalid message format', 'code' => 100 } }.to_json,
            parsed_response: { 'error' => { 'message' => 'Invalid message format', 'code' => 100 } }
          )

          allow(HTTParty).to receive(:post).and_return(error_response)

          described_class.new(message: message).perform

          expect(message.reload.status).to eq('failed')
          expect(message.reload.external_error).to eq('100 - Invalid message format')
        end

        it 'handles reauthorization errors if access token is expired' do
          message = create(:message, message_type: 'outgoing', inbox: instagram_inbox, account: account, conversation: conversation)

          error_response = instance_double(
            HTTParty::Response,
            success?: false,
            body: { 'error' => { 'message' => 'Access token has expired', 'code' => 190 } }.to_json,
            parsed_response: { 'error' => { 'message' => 'Access token has expired', 'code' => 190 } }
          )

          allow(HTTParty).to receive(:post).and_return(error_response)

          described_class.new(message: message).perform

          expect(message.reload.status).to eq('failed')
          expect(message.reload.external_error).to eq('190 - Access token has expired')
          expect(instagram_channel.reload).to be_reauthorization_required
        end
      end
    end
  end
end
