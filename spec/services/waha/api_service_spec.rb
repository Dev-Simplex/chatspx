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
end
