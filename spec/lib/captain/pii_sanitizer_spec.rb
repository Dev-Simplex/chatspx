require 'rails_helper'

RSpec.describe Captain::PiiSanitizer do
  describe '.sanitize' do
    context 'with CPF' do
      it 'redacts a CPF with dots and dash' do
        expect(described_class.sanitize('CPF 123.456.789-09 ok')).to eq('CPF [CPF] ok')
      end

      it 'redacts a CPF with no punctuation' do
        expect(described_class.sanitize('CPF 12345678909')).to eq('CPF [CPF]')
      end

      it 'does not redact all-same-digit fake CPF' do
        expect(described_class.sanitize('CPF 00000000000')).to eq('CPF 00000000000')
      end
    end

    context 'with CNPJ' do
      it 'redacts a CNPJ with full punctuation' do
        expect(described_class.sanitize('CNPJ 12.345.678/0001-90')).to eq('CNPJ [CNPJ]')
      end

      it 'redacts a CNPJ with no punctuation' do
        expect(described_class.sanitize('CNPJ 12345678000190')).to eq('CNPJ [CNPJ]')
      end
    end

    context 'with phone numbers' do
      it 'redacts a BR mobile with country code' do
        expect(described_class.sanitize('Liga: +55 11 91234-5678')).to eq('Liga: [TELEFONE]')
      end

      it 'redacts a BR mobile in DDD format' do
        expect(described_class.sanitize('Liga (11) 91234-5678')).to eq('Liga [TELEFONE]')
      end

      it 'redacts a compact BR mobile' do
        expect(described_class.sanitize('11912345678')).to eq('[TELEFONE]')
      end
    end

    context 'with credit cards' do
      it 'redacts a Luhn-valid card' do
        # 4111 1111 1111 1111 — Visa test number, valid Luhn
        expect(described_class.sanitize('Cartao 4111 1111 1111 1111')).to eq('Cartao [CARTAO]')
      end

      it 'does not redact Luhn-invalid 16 digits' do
        expect(described_class.sanitize('barcode 1234567890123456')).to eq('barcode 1234567890123456')
      end

      it 'does not redact 20-digit barcodes' do
        expect(described_class.sanitize('barcode 12345678901234567890')).to eq('barcode 12345678901234567890')
      end
    end

    context 'with email and CEP (off by default)' do
      it 'does NOT redact email by default' do
        expect(described_class.sanitize('contato: foo@example.com')).to eq('contato: foo@example.com')
      end

      it 'redacts email when explicitly enabled' do
        expect(described_class.sanitize('foo@example.com', enabled_types: %i[email])).to eq('[EMAIL]')
      end

      it 'does NOT redact CEP by default' do
        expect(described_class.sanitize('CEP 01310-100')).to eq('CEP 01310-100')
      end

      it 'redacts CEP when explicitly enabled' do
        expect(described_class.sanitize('CEP 01310-100', enabled_types: %i[cep])).to eq('CEP [CEP]')
      end
    end

    context 'with edge cases' do
      it 'returns blank input unchanged' do
        expect(described_class.sanitize('')).to eq('')
        expect(described_class.sanitize(nil)).to be_nil
      end

      it 'redacts multiple distinct types in a single string' do
        text = 'CPF 123.456.789-09 e CNPJ 12.345.678/0001-90'
        expect(described_class.sanitize(text)).to eq('CPF [CPF] e CNPJ [CNPJ]')
      end

      it 'is fast on large strings' do
        text = 'x' * 10_000
        t0 = Time.current
        described_class.sanitize(text)
        elapsed_ms = (Time.current - t0) * 1000
        expect(elapsed_ms).to be < 50
      end
    end
  end

  describe '.valid_luhn?' do
    it 'rejects nil and non-numeric' do
      expect(described_class.valid_luhn?('')).to be false
      expect(described_class.valid_luhn?('abc')).to be false
    end

    it 'rejects strings with wrong length' do
      expect(described_class.valid_luhn?('123')).to be false
      expect(described_class.valid_luhn?('12345678901234567890')).to be false
    end

    it 'accepts the Visa test number' do
      expect(described_class.valid_luhn?('4111111111111111')).to be true
    end

    it 'rejects a near-Luhn number' do
      expect(described_class.valid_luhn?('4111111111111112')).to be false
    end
  end
end
