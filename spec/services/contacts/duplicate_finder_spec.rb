require 'rails_helper'

describe Contacts::DuplicateFinder do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }

  def find(*contacts)
    described_class.new(account: account, contacts: contacts).perform
  end

  it 'links the contact whose number is held by the whatsapp link of another contact (S-02)' do
    wrong = create(:contact, account: account, phone_number: '+5565992476382')
    create(:contact_inbox, contact: wrong, inbox: inbox, source_id: '5565992476302')
    right = create(:contact, account: account, phone_number: '+5565992476302')

    expect(find(wrong, right)).to eq(wrong.id => right.id, right.id => wrong.id)
  end

  it 'matches the other ninth-digit form of the number' do
    legacy = create(:contact, account: account)
    create(:contact_inbox, contact: legacy, inbox: inbox, source_id: '556592476302')
    current = create(:contact, account: account, phone_number: '+5565992476302')

    expect(find(current)).to eq(current.id => legacy.id)
  end

  it 'does not flag a contact because of its own whatsapp link' do
    contact = create(:contact, account: account, phone_number: '+5565992476302')
    create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5565992476302')

    expect(find(contact)).to eq({})
  end

  it 'ignores contacts and links of another account' do
    other_account = create(:account)
    other_inbox = create(:channel_whatsapp, account: other_account, sync_templates: false, validate_provider_config: false).inbox
    create(:contact, account: other_account, phone_number: '+5565992476302')
    create(:contact_inbox, contact: create(:contact, account: other_account), inbox: other_inbox, source_id: '5565992476302')
    contact = create(:contact, account: account, phone_number: '+5565992476302')

    expect(find(contact)).to eq({})
  end

  it 'returns nothing for contacts without phone or links' do
    expect(find(create(:contact, :with_email, account: account))).to eq({})
  end
end
