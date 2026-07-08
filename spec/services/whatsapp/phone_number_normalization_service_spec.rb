require 'rails_helper'

describe Whatsapp::PhoneNumberNormalizationService do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
  let(:inbox) { whatsapp_channel.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:service) { described_class.new(inbox) }

  describe '#normalize_and_find_contact_by_provider' do
    context 'with Brazilian numbers via cloud provider' do
      it 'matches a 13-digit waid against a CI stored with 12 digits' do
        create(:contact_inbox, contact: contact, inbox: inbox, source_id: '556696636632')

        result = service.normalize_and_find_contact_by_provider('5566996636632', :cloud)

        expect(result).to eq('556696636632')
      end

      it 'matches a 12-digit waid against a CI stored with 13 digits' do
        create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5566996636632')

        result = service.normalize_and_find_contact_by_provider('556696636632', :cloud)

        expect(result).to eq('5566996636632')
      end

      it 'returns the raw number when no CI exists in any variant' do
        result = service.normalize_and_find_contact_by_provider('5566996636632', :cloud)

        expect(result).to eq('5566996636632')
      end

      it 'returns the waid unchanged when the CI already matches the incoming format' do
        create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5566996636632')

        result = service.normalize_and_find_contact_by_provider('5566996636632', :cloud)

        expect(result).to eq('5566996636632')
      end

      it 'returns the 13-digit CI when both 12- and 13-digit variants already exist' do
        # Existing legacy duplicates: until the data-merge step runs, the service should
        # keep traffic flowing to the canonical current-format CI (13d) rather than the legacy one.
        create(:contact_inbox, contact: contact, inbox: inbox, source_id: '556696636632')
        create(:contact_inbox, contact: create(:contact, account: account), inbox: inbox, source_id: '5566996636632')

        result = service.normalize_and_find_contact_by_provider('5566996636632', :cloud)

        expect(result).to eq('5566996636632')
      end

      it 'routes to the ficha whose conversation is most recent when duplicates exist' do
        # Same lead, two fichas (ninth-digit duplication). The 13-digit ficha is the FIRST
        # variant tried, but its thread is stale; the live thread sits on the 12-digit ficha.
        # The reply must follow the live thread, not whichever variant matched first.
        ci_13 = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5566996636632')
        contact_12 = create(:contact, account: account)
        ci_12 = create(:contact_inbox, contact: contact_12, inbox: inbox, source_id: '556696636632')

        create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: ci_13, created_at: 10.days.ago)
        create(:conversation, account: account, inbox: inbox, contact: contact_12, contact_inbox: ci_12, created_at: 1.hour.ago)

        result = service.normalize_and_find_contact_by_provider('5566996636632', :cloud)

        expect(result).to eq('556696636632')
      end
    end

    context 'with non-Brazilian numbers' do
      it 'returns the raw number when no normalizer handles the country code' do
        result = service.normalize_and_find_contact_by_provider('14155551212', :cloud)

        expect(result).to eq('14155551212')
      end
    end
  end
end
