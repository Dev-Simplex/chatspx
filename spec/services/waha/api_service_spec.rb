# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Waha::ApiService do
  subject(:service) { described_class.new }

  before do
    stub_const('ENV', ENV.to_h.merge('WAHA_API_URL' => 'https://waha.example.com', 'WAHA_API_KEY' => 'k'))
  end

  describe '#send_location' do
    let(:response_body) { { 'id' => 'msg-1' }.to_json }

    it 'POSTs to /api/sendLocation with chatId, latitude and longitude' do
      stub = stub_request(:post, 'https://waha.example.com/api/sendLocation')
             .with(
               headers: { 'Content-Type' => 'application/json', 'X-Api-Key' => 'k' },
               body: { session: 'default', chatId: '5511@c.us', latitude: -15.6, longitude: -56.1 }.to_json
             )
             .to_return(status: 200, body: response_body)

      result = service.send_location(session: 'default', chat_id: '5511@c.us', latitude: -15.6, longitude: -56.1)

      expect(stub).to have_been_requested
      expect(result).to eq('id' => 'msg-1')
    end

    it 'includes accuracy when provided' do
      stub = stub_request(:post, 'https://waha.example.com/api/sendLocation')
             .with(body: hash_including(accuracy: 25))
             .to_return(status: 200, body: response_body)

      service.send_location(session: 'default', chat_id: '5511@c.us', latitude: -15.6, longitude: -56.1, accuracy: 25)

      expect(stub).to have_been_requested
    end

    it 'omits accuracy when nil' do
      stub = stub_request(:post, 'https://waha.example.com/api/sendLocation').to_return(status: 200, body: response_body)

      service.send_location(session: 'default', chat_id: '5511@c.us', latitude: -15.6, longitude: -56.1)

      expect(stub.with { |req| !JSON.parse(req.body).key?('accuracy') }).to have_been_requested
    end
  end

  describe '#send_contact_vcard' do
    it 'POSTs the contactsIds array (plural) to /api/sendContactVcard' do
      stub = stub_request(:post, 'https://waha.example.com/api/sendContactVcard')
             .with(body: { session: 'default', chatId: '5511@c.us', contactsIds: ['5511988887777@c.us'] }.to_json)
             .to_return(status: 200, body: { 'id' => 'm-1' }.to_json)

      service.send_contact_vcard(session: 'default', chat_id: '5511@c.us', contact_ids: ['5511988887777@c.us'])

      expect(stub).to have_been_requested
    end

    it 'normalizes scalar arg to single-element array' do
      stub = stub_request(:post, 'https://waha.example.com/api/sendContactVcard')
             .with(body: { session: 'default', chatId: '5511@c.us', contactsIds: ['5511988887777@c.us'] }.to_json)
             .to_return(status: 200, body: { 'id' => 'm-1' }.to_json)

      service.send_contact_vcard(session: 'default', chat_id: '5511@c.us', contact_ids: '5511988887777@c.us')

      expect(stub).to have_been_requested
    end
  end

  describe '#send_text_with_vcard' do
    it 'POSTs a vCard 3.0 string through /api/sendText' do
      stub = stub_request(:post, 'https://waha.example.com/api/sendText')
             .with do |req|
               body = JSON.parse(req.body)
               body['session'] == 'default' &&
                 body['chatId'] == '5511@c.us' &&
                 body['text'].include?('BEGIN:VCARD') &&
                 body['text'].include?('FN:Maria Cliente') &&
                 body['text'].include?('TEL;TYPE=CELL:+5511999998888') &&
                 body['text'].include?('END:VCARD')
             end
             .to_return(status: 200, body: { 'id' => 'm-2' }.to_json)

      service.send_text_with_vcard(session: 'default', chat_id: '5511@c.us', name: 'Maria Cliente', phone: '5511999998888')

      expect(stub).to have_been_requested
    end
  end

  describe '#build_vcard' do
    it 'normalizes phone with leading + and renders FN/TEL lines' do
      vcard = service.build_vcard(name: 'Joana', phone: '5511999998888')

      expect(vcard).to include('BEGIN:VCARD', 'VERSION:3.0', 'FN:Joana', 'TEL;TYPE=CELL:+5511999998888', 'END:VCARD')
    end

    it 'strips CR/LF from name to avoid header injection' do
      vcard = service.build_vcard(name: "Mal\r\nIntencionado", phone: '+5511999998888')

      expect(vcard).not_to include("\r")
      expect(vcard).to match(/FN:Mal\s+Intencionado/)
    end
  end

  describe '#send_list' do
    # GOWS payload: message wraps title (required) + button (required) + sections.
    # description is omitted when no explicit title is given; row description is
    # omitted when blank.
    it 'POSTs a GOWS-shaped list payload (title + button) to /api/sendList' do
      stub = stub_request(:post, 'https://waha.example.com/api/sendList')
             .with(body: {
               session: 'default',
               chatId: '5511@c.us',
               message: {
                 title: 'Escolha um setor',
                 button: 'Menu',
                 sections: [{
                   title: 'Menu',
                   rows: [
                     { rowId: 'fin', title: 'Financeiro' },
                     { rowId: 'sup', title: 'Suporte' }
                   ]
                 }]
               }
             }.to_json)
             .to_return(status: 200, body: { 'id' => 'list-1' }.to_json)

      result = service.send_list(
        session: 'default', chat_id: '5511@c.us', body: 'Escolha um setor', button_text: 'Menu',
        sections: [{ title: 'Menu', rows: [
          { rowId: 'fin', title: 'Financeiro', description: '' },
          { rowId: 'sup', title: 'Suporte', description: '' }
        ] }]
      )

      expect(stub).to have_been_requested
      expect(result).to eq('id' => 'list-1')
    end
  end

  describe '#send_poll' do
    # Native WhatsApp poll — the reliable interactive format on GOWS PLUS.
    it 'POSTs a poll payload (name + options + multipleAnswers) to /api/sendPoll' do
      stub = stub_request(:post, 'https://waha.example.com/api/sendPoll')
             .with(body: {
               session: 'default',
               chatId: '5511@c.us',
               poll: {
                 name: 'Como foi o atendimento?',
                 options: %w[Ótimo Bom Regular],
                 multipleAnswers: false
               }
             }.to_json)
             .to_return(status: 201, body: { 'id' => 'poll-1' }.to_json)

      result = service.send_poll(
        session: 'default', chat_id: '5511@c.us',
        name: 'Como foi o atendimento?', options: %w[Ótimo Bom Regular]
      )

      expect(stub).to have_been_requested
      expect(result).to eq('id' => 'poll-1')
    end

    it 'coerces multiple_answers to a real boolean' do
      stub = stub_request(:post, 'https://waha.example.com/api/sendPoll')
             .with(body: hash_including('poll' => hash_including('multipleAnswers' => true)))
             .to_return(status: 201, body: { 'id' => 'poll-2' }.to_json)

      service.send_poll(session: 'default', chat_id: '5511@c.us', name: 'Q', options: %w[a b], multiple_answers: 'yes')

      expect(stub).to have_been_requested
    end
  end

  describe '#send_text' do
    it 'POSTs plain text to /api/sendText' do
      stub = stub_request(:post, 'https://waha.example.com/api/sendText')
             .with(body: { session: 'default', chatId: '5511@c.us', text: "Escolha:\n1. A\n2. B" }.to_json)
             .to_return(status: 200, body: { 'id' => 'txt-1' }.to_json)

      service.send_text(session: 'default', chat_id: '5511@c.us', text: "Escolha:\n1. A\n2. B")

      expect(stub).to have_been_requested
    end
  end
end
