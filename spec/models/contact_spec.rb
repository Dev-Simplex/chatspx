# frozen_string_literal: true

require 'rails_helper'

require Rails.root.join 'spec/models/concerns/avatarable_shared.rb'

RSpec.describe Contact do
  context 'with validations' do
    it { is_expected.to validate_presence_of(:account_id) }
  end

  context 'with associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:conversations).dependent(:destroy_async) }
  end

  describe 'concerns' do
    it_behaves_like 'avatarable'

    it 'accepts webp avatars' do
      contact = build(:contact, account: create(:account))
      contact.avatar.attach(get_blob_for(Rails.root.join('spec/assets/avatar.png'), 'image/webp'))

      expect(contact).to be_valid
    end
  end

  context 'when prepare contact attributes before validation' do
    it 'sets email to lowercase' do
      contact = create(:contact, email: 'Test@test.com')
      expect(contact.email).to eq('test@test.com')
      expect(contact.contact_type).to eq('lead')
    end

    it 'sets email to nil when empty string' do
      contact = create(:contact, email: '')
      expect(contact.email).to be_nil
      expect(contact.contact_type).to eq('visitor')
    end

    it 'sets custom_attributes to {} when nil' do
      contact = create(:contact, custom_attributes: nil)
      expect(contact.custom_attributes).to eq({})
    end

    it 'sets custom_attributes to {} when empty string' do
      contact = create(:contact, custom_attributes: '')
      expect(contact.custom_attributes).to eq({})
    end

    it 'sets additional_attributes to {} when nil' do
      contact = create(:contact, additional_attributes: nil)
      expect(contact.additional_attributes).to eq({})
    end

    it 'sets additional_attributes to {} when empty string' do
      contact = create(:contact, additional_attributes: '')
      expect(contact.additional_attributes).to eq({})
    end
  end

  # O contato nao tinha teto NENHUM de custom_attributes — nem de tamanho por
  # valor, nem de quantidade de chaves — apesar de o widget escrever nele a
  # partir do site do cliente. Conversation e Company ja validavam; o contato nao.
  describe 'teto de custom_attributes' do
    let(:account) { create(:account) }
    let(:max_keys) { described_class::CUSTOM_ATTRIBUTES_MAX_KEYS }

    def attributes_with(count, prefix: 'chave')
      (1..count).to_h { |index| ["#{prefix}_#{index}", "valor #{index}"] }
    end

    it 'aceita exatamente o teto de chaves' do
      contact = build(:contact, account: account, custom_attributes: attributes_with(max_keys))

      expect(contact).to be_valid
      expect(contact.custom_attributes.size).to eq(50)
    end

    it 'recusa uma chave acima do teto, com erro legivel' do
      contact = build(:contact, account: account, custom_attributes: attributes_with(max_keys + 1))

      expect(contact).not_to be_valid
      expect(contact.errors[:custom_attributes]).to eq(['cannot have more than 50 attributes (got 51)'])
    end

    it 'recusa valor de texto acima de 1500 caracteres' do
      contact = build(:contact, account: account, custom_attributes: { 'bio' => 'a' * 1501 })

      expect(contact).not_to be_valid
      expect(contact.errors[:custom_attributes]).to eq(['bio length should be < 1500'])
    end

    it 'aceita valor de texto com exatamente 1500 caracteres' do
      contact = build(:contact, account: account, custom_attributes: { 'bio' => 'a' * 1500 })

      expect(contact).to be_valid
    end

    it 'recusa inteiro acima do teto' do
      contact = build(:contact, account: account, custom_attributes: { 'saldo' => 10_000_000_000 })

      expect(contact).not_to be_valid
      expect(contact.errors[:custom_attributes]).to eq(['saldo value should be < 9999999999'])
    end

    # O teto de TAMANHO so olhava String e Integer no TOPO do hash: um valor
    # ANINHADO passava inteiro, com qualquer tamanho. Por isso ele agora e de
    # BYTES do jsonb serializado e de PROFUNDIDADE, nao so das chaves de topo.
    context 'when the value is nested' do
      let(:max_bytes) { described_class::CUSTOM_ATTRIBUTES_MAX_BYTES }
      let(:max_depth) { described_class::CUSTOM_ATTRIBUTES_MAX_DEPTH }

      # ~81 KB com TODA string abaixo de 1500 e uma unica chave de topo: nenhuma
      # das regras antigas (50 chaves, 1500 por string) morde nisto.
      def nested_bag(entries)
        (1..entries).to_h { |index| ["chave_#{index}", 'a' * 1000] }
      end

      it 'recusa jsonb aninhado acima do teto de bytes' do
        contact = build(:contact, account: account, custom_attributes: { 'bag' => nested_bag(80) })

        expect(contact).not_to be_valid
        expect(contact.errors[:custom_attributes].first).to match(/\Atotal size should be at most 65536 bytes \(got \d{5,}\)\z/)
      end

      it 'aceita o mesmo formato abaixo do teto de bytes' do
        contact = build(:contact, account: account, custom_attributes: { 'bag' => nested_bag(40) })

        expect(contact).to be_valid
        expect(contact.custom_attributes.to_json.bytesize).to be <= max_bytes
      end

      it 'recusa profundidade acima do teto' do
        contact = build(:contact, account: account, custom_attributes: { 'a' => { 'b' => { 'c' => { 'd' => 1 } } } })

        expect(contact).not_to be_valid
        expect(contact.errors[:custom_attributes]).to eq(['nesting should be at most 3 levels deep (got 4)'])
      end

      it 'aceita profundidade exatamente no teto' do
        contact = build(:contact, account: account, custom_attributes: { 'a' => { 'b' => { 'c' => 1 } } })

        expect(contact).to be_valid
        expect(max_depth).to eq(3)
      end

      it 'conta array como um nivel' do
        contact = build(:contact, account: account, custom_attributes: { 'a' => { 'b' => [{ 'c' => 1 }] } })

        expect(contact).not_to be_valid
        expect(contact.errors[:custom_attributes]).to eq(['nesting should be at most 3 levels deep (got 4)'])
      end

      # Mesma regra do teto de chaves: quem ja estourou continua salvando.
      context 'when the contact already blew past the byte cap' do
        let(:contact) do
          record = build(:contact, account: account, custom_attributes: { 'bag' => nested_bag(80) })
          record.save!(validate: false)
          record.reload
        end

        it 'nasceu acima do teto de bytes' do
          expect(contact.custom_attributes.to_json.bytesize).to be > max_bytes
        end

        it 'continua salvando edicao que nao mexe no jsonb' do
          contact.name = 'Nome novo'

          expect(contact.save).to be(true)
        end

        it 'recusa quando o jsonb cresce' do
          contact.custom_attributes = contact.custom_attributes.merge('bag2' => nested_bag(10))

          expect(contact.save).to be(false)
          expect(contact.errors[:custom_attributes].first).to start_with('total size should be at most 65536 bytes')
        end

        it 'aceita quando o jsonb encolhe, mesmo seguindo acima do teto' do
          contact.custom_attributes = { 'bag' => nested_bag(70) }

          expect(contact.save).to be(true)
          expect(contact.reload.custom_attributes.to_json.bytesize).to be > max_bytes
        end
      end
    end

    # A validacao morde no CRESCIMENTO, nao no estado. Um teto novo nao pode
    # travar a edicao de nome e telefone de contato historico que ja passou dele.
    context 'when the contact already blew past the cap before the validation existed' do
      let(:contact) do
        record = build(:contact, account: account, custom_attributes: attributes_with(80))
        record.save!(validate: false)
        record.reload
      end

      it 'nasceu com 80 chaves, acima do teto' do
        expect(contact.custom_attributes.size).to eq(80)
      end

      it 'continua salvando edicao que nao mexe no jsonb' do
        contact.name = 'Nome novo'

        expect(contact.save).to be(true)
        expect(contact.reload.name).to eq('Nome novo')
      end

      it 'continua salvando quando o jsonb encolhe, mesmo seguindo acima do teto' do
        contact.custom_attributes = attributes_with(70)

        expect(contact.save).to be(true)
        expect(contact.reload.custom_attributes.size).to eq(70)
      end

      it 'recusa quando o jsonb cresce' do
        contact.custom_attributes = attributes_with(81)

        expect(contact.save).to be(false)
        expect(contact.errors[:custom_attributes]).to eq(['cannot have more than 50 attributes (got 81)'])
        expect(contact.reload.custom_attributes.size).to eq(80)
      end
    end
  end

  context 'when phone number format' do
    it 'will throw error for existing invalid phone number' do
      contact = create(:contact)
      expect { contact.update!(phone_number: '123456789') }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'updates phone number when adding valid phone number' do
      contact = create(:contact)
      expect(contact.update!(phone_number: '+12312312321')).to be true
      expect(contact.phone_number).to eq '+12312312321'
    end
  end

  context 'when email format' do
    it 'will throw error for existing invalid email' do
      contact = create(:contact)
      expect { contact.update!(email: '<2324234234') }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'updates email when adding valid email' do
      contact = create(:contact)
      expect(contact.update!(email: 'test@test.com')).to be true
      expect(contact.email).to eq 'test@test.com'
    end
  end

  context 'when city and country code passed in additional attributes' do
    it 'updates location and country code' do
      contact = create(:contact, additional_attributes: { city: 'New York', country: 'US' })
      expect(contact.location).to eq 'New York'
      expect(contact.country_code).to eq 'US'
    end
  end

  context 'when a contact is created' do
    it 'has contact type "visitor" by default' do
      contact = create(:contact)
      expect(contact.contact_type).to eq 'visitor'
    end

    it 'has contact type "lead" when email is present' do
      contact = create(:contact, email: 'test@test.com')
      expect(contact.contact_type).to eq 'lead'
    end

    it 'has contact type "lead" when contacted through a social channel' do
      contact = create(:contact, additional_attributes: { social_facebook_user_id: '123' })
      expect(contact.contact_type).to eq 'lead'
    end
  end

  describe '.resolved_contacts' do
    let(:account) { create(:account) }

    context 'when crm_v2 feature flag is disabled' do
      it 'returns contacts with email, phone_number, or identifier using feature flag value' do
        # Create contacts with different attributes
        contact_with_email = create(:contact, account: account, email: 'test@example.com', name: 'John Doe')
        contact_with_phone = create(:contact, account: account, phone_number: '+1234567890', name: 'Jane Smith')
        contact_with_identifier = create(:contact, account: account, identifier: 'user123', name: 'Bob Wilson')
        contact_without_details = create(:contact, account: account, name: 'Alice Johnson', email: nil, phone_number: nil, identifier: nil)

        resolved = account.contacts.resolved_contacts(use_crm_v2: false)

        expect(resolved).to include(contact_with_email, contact_with_phone, contact_with_identifier)
        expect(resolved).not_to include(contact_without_details)
      end
    end

    context 'when crm_v2 feature flag is enabled' do
      it 'returns only contacts with contact_type lead' do
        # Contact with email and phone - should be marked as lead
        contact_with_details = create(:contact, account: account, email: 'customer@example.com', phone_number: '+1234567890', name: 'Customer One')
        expect(contact_with_details.contact_type).to eq('lead')

        # Contact without email/phone - should be marked as visitor
        contact_without_details = create(:contact, account: account, name: 'Lead', email: nil, phone_number: nil)
        expect(contact_without_details.contact_type).to eq('visitor')

        # Force set contact_type to lead for testing
        contact_without_details.update!(contact_type: 'lead')

        resolved = account.contacts.resolved_contacts(use_crm_v2: true)

        expect(resolved).to include(contact_with_details)
        expect(resolved).to include(contact_without_details)
      end

      it 'includes all lead contacts regardless of email/phone presence' do
        # Create a lead contact with only name
        lead_contact = create(:contact, account: account, name: 'Test Lead')
        lead_contact.update!(contact_type: 'lead')

        # Create a customer contact
        customer_contact = create(:contact, account: account, email: 'customer@test.com')
        customer_contact.update!(contact_type: 'customer')

        # Create a visitor contact
        visitor_contact = create(:contact, account: account, name: 'Visitor')
        expect(visitor_contact.contact_type).to eq('visitor')

        resolved = account.contacts.resolved_contacts(use_crm_v2: true)

        expect(resolved).to include(lead_contact)
        expect(resolved).not_to include(customer_contact)
        expect(resolved).not_to include(visitor_contact)
      end

      it 'returns contacts with email, phone_number, or identifier when explicitly passing use_crm_v2: false' do
        # Even though feature flag is enabled, we're explicitly passing false
        contact_with_email = create(:contact, account: account, email: 'test@example.com', name: 'John Doe')
        contact_with_phone = create(:contact, account: account, phone_number: '+1234567890', name: 'Jane Smith')
        contact_without_details = create(:contact, account: account, name: 'Alice Johnson', email: nil, phone_number: nil, identifier: nil)

        resolved = account.contacts.resolved_contacts(use_crm_v2: false)

        # Should use the old logic despite feature flag being enabled
        expect(resolved).to include(contact_with_email, contact_with_phone)
        expect(resolved).not_to include(contact_without_details)
      end
    end

    context 'with mixed contact types' do
      it 'correctly filters based on use_crm_v2 parameter regardless of feature flag' do
        # Create different types of contacts
        visitor_contact = create(:contact, account: account, name: 'Visitor')
        lead_with_email = create(:contact, account: account, email: 'lead@example.com', name: 'Lead')
        lead_without_email = create(:contact, account: account, name: 'Lead Only')
        lead_without_email.update!(contact_type: 'lead')
        customer_contact = create(:contact, account: account, email: 'customer@example.com', name: 'Customer')
        customer_contact.update!(contact_type: 'customer')

        # Test with use_crm_v2: false
        resolved_old = account.contacts.resolved_contacts(use_crm_v2: false)
        expect(resolved_old).to include(lead_with_email, customer_contact)
        expect(resolved_old).not_to include(visitor_contact, lead_without_email)

        # Test with use_crm_v2: true
        resolved_new = account.contacts.resolved_contacts(use_crm_v2: true)
        expect(resolved_new).to include(lead_with_email, lead_without_email)
        expect(resolved_new).not_to include(visitor_contact, customer_contact)
      end
    end
  end
end
