# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Contacts::ResolveLidJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, waha_session_name: 'spx-test') }
  let(:resolved_jid) { '5511999999999@c.us' }
  # O BrazilPhoneNormalizer roda IGUAL no job e no save do contato (mesma entrada),
  # entao o telefone resolvido pelo job bate com o phone_number persistido.
  let(:normalized_phone) { Contacts::BrazilPhoneNormalizer.normalize('+5511999999999') }

  describe '#perform' do
    # Bug central: ate o fix, este cenario caia no branch inline e estourava
    # ActiveRecord::RecordInvalid "Phone number has already been taken".
    context 'when the resolved phone already belongs to ANOTHER contact (conflito de telefone, sem contact_inbox==pn)' do
      let!(:existing_contact) do
        create(:contact, account: account, name: 'Cliente Real', phone_number: '+5511999999999')
      end
      let!(:lid_contact) do
        create(:contact, account: account, name: '5511999999999@lid', identifier: '5511999999999@lid',
                         phone_number: nil, custom_attributes: { 'waha_whatsapp_jid' => resolved_jid })
      end
      let!(:lid_contact_inbox) do
        create(:contact_inbox, contact: lid_contact, inbox: inbox, source_id: '5511999999999@lid')
      end

      it 'mescla no contato existente em vez de estourar RecordInvalid' do
        expect { described_class.perform_now(lid_contact_inbox.id) }.not_to raise_error
        expect { lid_contact.reload }.to raise_error(ActiveRecord::RecordNotFound)
        expect(existing_contact.reload.phone_number).to eq(normalized_phone)
      end

      it 'reatribui o contact_inbox @lid ao contato existente e normaliza o source_id para o JID' do
        described_class.perform_now(lid_contact_inbox.id)

        lid_contact_inbox.reload
        expect(lid_contact_inbox.contact_id).to eq(existing_contact.id)
        expect(lid_contact_inbox.source_id).to eq(resolved_jid)
      end
    end

    # ContactMergeAction faz deep_merge: se o base tinha name/identifier vazios, ele
    # HERDA o @lid do mergee. O fix limpa esse residuo.
    context 'when the merge would leave residual @lid on the base contact' do
      let!(:existing_contact) do
        create(:contact, account: account, name: '', identifier: nil, phone_number: '+5511999999999')
      end
      let!(:lid_contact) do
        create(:contact, account: account, name: '5511999999999@lid', identifier: '5511999999999@lid',
                         phone_number: nil, custom_attributes: { 'waha_whatsapp_jid' => resolved_jid })
      end
      let!(:lid_contact_inbox) do
        create(:contact_inbox, contact: lid_contact, inbox: inbox, source_id: '5511999999999@lid')
      end

      it 'limpa identifier e name @lid residuais no contato base' do
        described_class.perform_now(lid_contact_inbox.id)

        existing_contact.reload
        expect(existing_contact.identifier).to be_nil
        expect(existing_contact.name).not_to end_with('@lid')
        expect(existing_contact.name).to eq(normalized_phone)
      end
    end

    context 'when an existing contact_inbox already carries the JID (source_id == pn)' do
      let!(:existing_contact) { create(:contact, account: account, name: 'Cliente Real') }
      let!(:pn_contact_inbox) do
        create(:contact_inbox, contact: existing_contact, inbox: inbox, source_id: resolved_jid)
      end
      let!(:lid_contact) do
        create(:contact, account: account, name: '5511999999999@lid', identifier: '5511999999999@lid',
                         phone_number: nil, custom_attributes: { 'waha_whatsapp_jid' => resolved_jid })
      end
      let!(:lid_contact_inbox) do
        create(:contact_inbox, contact: lid_contact, inbox: inbox, source_id: '5511999999999@lid')
      end

      it 'mescla no contato do contact_inbox==pn e remove o contact_inbox @lid redundante' do
        described_class.perform_now(lid_contact_inbox.id)

        expect { lid_contact.reload }.to raise_error(ActiveRecord::RecordNotFound)
        expect { lid_contact_inbox.reload }.to raise_error(ActiveRecord::RecordNotFound)
        expect(pn_contact_inbox.reload.contact_id).to eq(existing_contact.id)
      end
    end

    context 'when there is no conflict (caminho feliz)' do
      let!(:lid_contact) do
        create(:contact, account: account, name: '5511999999999@lid', identifier: '5511999999999@lid',
                         phone_number: nil, custom_attributes: { 'waha_whatsapp_jid' => resolved_jid })
      end
      let!(:lid_contact_inbox) do
        create(:contact_inbox, contact: lid_contact, inbox: inbox, source_id: '5511999999999@lid')
      end

      it 'resolve inline: seta phone, limpa identifier, normaliza name e source_id' do
        described_class.perform_now(lid_contact_inbox.id)

        lid_contact.reload
        lid_contact_inbox.reload
        expect(lid_contact.phone_number).to eq(normalized_phone)
        expect(lid_contact.identifier).to be_nil
        expect(lid_contact.name).to eq(normalized_phone)
        expect(lid_contact_inbox.source_id).to eq(resolved_jid)
      end
    end
  end
end
