require 'rails_helper'

RSpec.describe Vcard::ParserService do
  describe '#parse' do
    it 'parses a vCard 3.0 with N, FN, TEL and ORG' do
      raw = <<~VCARD
        BEGIN:VCARD
        VERSION:3.0
        N:Doe;John;;;
        FN:John Doe
        ORG:Acme Inc.;Sales
        TEL;TYPE=CELL:+15551234567
        EMAIL:john@acme.test
        END:VCARD
      VCARD

      contact = described_class.new(raw).parse.first

      expect(contact[:first_name]).to eq('John')
      expect(contact[:last_name]).to eq('Doe')
      expect(contact[:full_name]).to eq('John Doe')
      expect(contact[:phone]).to eq('+15551234567')
      expect(contact[:organization]).to eq('Acme Inc.')
      expect(contact[:email]).to eq('john@acme.test')
    end

    it 'parses a vCard 2.1 with CRLF line endings and bare param flags' do
      raw = "BEGIN:VCARD\r\nVERSION:2.1\r\nN:Silva;Ana\r\nFN:Ana Silva\r\nTEL;CELL;VOICE:+5511988887777\r\nEND:VCARD\r\n"

      contact = described_class.new(raw).parse.first

      expect(contact[:first_name]).to eq('Ana')
      expect(contact[:last_name]).to eq('Silva')
      expect(contact[:phone]).to eq('+5511988887777')
    end

    it 'parses a vCard 4.0' do
      raw = <<~VCARD
        BEGIN:VCARD
        VERSION:4.0
        FN:Maria Souza
        TEL;TYPE=cell;VALUE=tel:+551133334444
        END:VCARD
      VCARD

      contact = described_class.new(raw).parse.first

      expect(contact[:full_name]).to eq('Maria Souza')
      expect(contact[:phone]).to eq('+551133334444')
    end

    it 'derives first/last name from FN when N is absent' do
      raw = "BEGIN:VCARD\nVERSION:3.0\nFN:Jane Mary Roe\nTEL:+10000000000\nEND:VCARD"

      contact = described_class.new(raw).parse.first

      expect(contact[:first_name]).to eq('Jane')
      expect(contact[:last_name]).to eq('Mary Roe')
    end

    it 'keeps the first phone and collects every TEL' do
      raw = <<~VCARD
        BEGIN:VCARD
        VERSION:3.0
        FN:Multi Phone
        TEL;TYPE=CELL:+1111111111
        TEL;TYPE=WORK:+2222222222
        END:VCARD
      VCARD

      contact = described_class.new(raw).parse.first

      expect(contact[:phone]).to eq('+1111111111')
      expect(contact[:phones]).to eq(['+1111111111', '+2222222222'])
    end

    it 'works without ORG' do
      raw = "BEGIN:VCARD\nVERSION:3.0\nFN:No Org\nTEL:+13334445555\nEND:VCARD"

      contact = described_class.new(raw).parse.first

      expect(contact).not_to have_key(:organization)
    end

    it 'decodes QUOTED-PRINTABLE accented names' do
      raw = "BEGIN:VCARD\nVERSION:2.1\nFN;ENCODING=QUOTED-PRINTABLE:Jo=C3=A3o Concei=C3=A7=C3=A3o\nTEL:+5500000000\nEND:VCARD"

      contact = described_class.new(raw).parse.first

      expect(contact[:full_name]).to eq('João Conceição')
    end

    it 'parses multiple vCards in a single payload' do
      raw = <<~VCARD
        BEGIN:VCARD
        VERSION:3.0
        FN:First Person
        TEL:+1111111111
        END:VCARD
        BEGIN:VCARD
        VERSION:3.0
        FN:Second Person
        TEL:+2222222222
        END:VCARD
      VCARD

      contacts = described_class.new(raw).parse

      expect(contacts.length).to eq(2)
      expect(contacts.map { |c| c[:full_name] }).to eq(['First Person', 'Second Person'])
    end

    it 'unfolds wrapped lines' do
      raw = "BEGIN:VCARD\nVERSION:3.0\nFN:Very Long\n  Name Here\nTEL:+1234567890\nEND:VCARD"

      contact = described_class.new(raw).parse.first

      expect(contact[:full_name]).to eq('Very Long Name Here')
    end

    it 'keeps URL photos but drops oversized inline base64 photos' do
      url_card = "BEGIN:VCARD\nVERSION:4.0\nFN:Has Photo\nPHOTO:https://example.test/p.jpg\nTEL:+1\nEND:VCARD"
      big_card = "BEGIN:VCARD\nVERSION:3.0\nFN:Big Photo\nPHOTO;ENCODING=b;TYPE=JPEG:#{'A' * 30_000}\nTEL:+2\nEND:VCARD"

      expect(described_class.new(url_card).parse.first[:photo]).to eq('https://example.test/p.jpg')
      expect(described_class.new(big_card).parse.first).not_to have_key(:photo)
    end

    it 'returns an empty array for blank or non-vCard input' do
      expect(described_class.new('').parse).to eq([])
      expect(described_class.new('just some text').parse).to eq([])
    end
  end
end
