require 'rails_helper'

RSpec.describe Captain::Tools::SensitiveDataSanitizer do
  describe '.sanitize' do
    it 'redacts CPF, phone, credentials and signed URLs in nested payloads' do
      payload = {
        cpf: '123.456.789-00',
        contact: { phone: '+55 (65) 99999-9999' },
        token: 'plain-secret',
        note: 'authorization=Bearer-secret',
        link: 'https://example.com/clinic?token=url-secret&expires=123'
      }

      sanitized = described_class.sanitize(payload)
      serialized = sanitized.inspect

      expect(serialized).not_to include('123.456.789-00', '99999-9999', 'plain-secret', 'Bearer-secret', 'url-secret')
      expect(sanitized[:cpf]).to eq('[REDACTED_CPF]')
      expect(sanitized[:contact][:phone]).to eq('[REDACTED_PHONE]')
      expect(sanitized[:token]).to eq('[REDACTED]')
      expect(sanitized[:link]).to eq('[REDACTED_SIGNED_URL]')
    end

    it 'preserves non-sensitive context' do
      text = 'Cliente quer exame na loja Matriz no período da tarde.'

      expect(described_class.sanitize(text)).to eq(text)
    end

    it 'redacts secrets from raw JSON strings and relative signed URLs' do
      text = '{"token":"json-secret","return_url":"/clinic/answer?signature=url-secret"}'

      sanitized = described_class.sanitize(text)

      expect(sanitized).not_to include('json-secret', 'url-secret')
      expect(sanitized).to include('[REDACTED]', '[REDACTED_SIGNED_URL]')
    end

    it 'redacts numeric identifiers by their semantic keys' do
      sanitized = described_class.sanitize(cpf: 123_456_789_00, fone1: 65_99999_9999)

      expect(sanitized).to eq(cpf: '[REDACTED_CPF]', fone1: '[REDACTED_PHONE]')
    end
  end
end
