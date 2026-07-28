require 'rails_helper'

RSpec.describe Meta::LeadAds::CreateConversationService, type: :service do
  let(:account) { create(:account) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { create(:inbox, channel: api_channel, account: account, waha_session_name: 'TestSession') }
  let(:hook_settings) do
    { 'page_id' => '5395008152', 'verify_token' => 'vt', 'app_secret' => 'sec',
      'page_access_token' => 'tok', 'target_inbox_id' => inbox.id, 'skip_initial_message' => true }
  end
  let(:hook) do
    create(:integrations_hook, account: account, app_id: 'meta_lead_ads', settings: hook_settings)
  end
  let(:lead) do
    { leadgen_id: '1563000004237', form_id: '2545984', ad_id: '1202544',
      full_name: 'Maria Souza', email: 'maria@example.com', phone_number: phone }
  end
  let(:phone) { nil }
  let(:service) { described_class.new(hook: hook, lead: lead) }

  def normalize(value)
    described_class.new(hook: hook, lead: lead.merge(phone_number: value)).send(:normalize_phone, value)
  end

  describe '#normalize_phone' do
    context 'with numbers that already are (or become) valid E.164' do
      it 'keeps a Brazilian mobile that already has the ninth digit' do
        expect(normalize('(66) 99999-9999')).to eq('+5566999999999')
      end

      # Caso pedido explicitamente: legado sem o nono dígito. Quem completa é o
      # BrazilPhoneNormalizer — a validação nova não pode barrar este caminho.
      it 'adds the ninth digit to a legacy Brazilian mobile (DDD + 8 digits)' do
        expect(normalize('66 9999-9999')).to eq('+5566999999999')
      end

      it 'leaves a Brazilian landline untouched (no ninth digit)' do
        expect(normalize('66 3531-1930')).to eq('+556635311930')
      end

      # Número estrangeiro: 12+ dígitos não recebem o prefixo 55 e passam intactos.
      it 'accepts a foreign number and does not brazilianize it' do
        expect(normalize('+351 912 345 678')).to eq('+351912345678')
      end

      context 'when the hook has a default DDD' do
        let(:hook_settings) { super().merge('default_ddd' => '66') }

        it 'prefixes the DDD on a number typed without it' do
          expect(normalize('99692-6393')).to eq('+5566996926393')
        end
      end
    end

    # Antes, tudo o que entrava saía: o normalizer nunca devolve nil, então lixo de
    # formulário aberto chegava ao Contact e estourava RecordInvalid dentro do job.
    context 'with input that cannot become valid E.164' do
      it 'rejects a number with a leading zero from the country code' do
        expect(normalize('0055 66 99999-9999')).to be_nil
      end

      it 'rejects a number that keeps a leading zero after normalization' do
        expect(normalize('0 9999-9999')).to be_nil
      end

      it 'rejects two numbers pasted into the same field (over 15 digits)' do
        expect(normalize('66999999999 66988888888')).to be_nil
      end

      it 'returns nil for blank input' do
        expect(normalize('   ')).to be_nil
      end

      it 'logs the rejected value masked' do
        allow(Rails.logger).to receive(:warn)

        normalize('0055 66 99999-9999')

        expect(Rails.logger).to have_received(:warn).with(/E\.164 descartado.*valor=\+\*+9999\z/)
      end
    end
  end

  describe '#perform with an unusable phone number' do
    let(:phone) { '0055 66 99999-9999' }

    it 'does not raise RecordInvalid and falls back to the existing "lead without phone" path' do
      expect { service.perform }.not_to raise_error
    end

    it 'creates the contact without a phone number and keys the contact inbox by leadgen_id' do
      conversation = service.perform

      expect(conversation).to be_present
      expect(conversation.contact.phone_number).to be_blank
      expect(conversation.contact_inbox.source_id).to eq("meta_lead:#{lead[:leadgen_id]}")
    end

    it 'does not send the initial message' do
      conversation = service.perform

      expect(conversation.messages).to be_empty
    end
  end
end
