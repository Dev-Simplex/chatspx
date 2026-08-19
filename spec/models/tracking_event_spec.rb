require 'rails_helper'

# Bloco 5.03 — o registro server-side do fato. Contrato em docs/tracking/contrato-de-eventos.md.
RSpec.describe TrackingEvent, type: :model do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  def build_event(attributes = {})
    described_class.new({ name: 'chatspx_conversation_resolved', account: account,
                          occurred_at: Time.current, dedup_key: 'fato-1' }.merge(attributes))
  end

  describe 'event_id' do
    it 'is generated on create as a v4 UUID' do
      event = build_event
      event.save!

      expect(event.event_id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
    end

    it 'keeps an event_id that the caller supplied' do
      event = build_event(event_id: '11111111-1111-4111-8111-111111111111')
      event.save!

      expect(event.reload.event_id).to eq('11111111-1111-4111-8111-111111111111')
    end

    it 'refuses two records with the same event_id' do
      build_event(event_id: '22222222-2222-4222-8222-222222222222').save!

      expect { build_event(event_id: '22222222-2222-4222-8222-222222222222', dedup_key: 'fato-2').save! }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'name format — the three rules of the contract' do
    it 'accepts a name of the canonical vocabulary' do
      expect(build_event(name: 'chatspx_lead')).to be_valid
    end

    it 'accepts a custom event from the customer site, since 5.16 allows it' do
      expect(build_event(name: 'chatspx_orcamento_pedido')).to be_valid
    end

    it 'refuses a name without the chatspx_ prefix, naming the rule' do
      event = build_event(name: 'conversation_resolved')

      expect(event).not_to be_valid
      expect(event.errors[:name]).to eq(['deve começar com chatspx_'])
    end

    it 'refuses a name that is not snake_case' do
      event = build_event(name: 'chatspx_Conversation_Resolved')

      expect(event).not_to be_valid
      expect(event.errors[:name]).to eq(['deve ser snake_case: minúsculas, dígitos e _'])
    end

    # 40 e limite do GA4, nao preferencia nossa: nome maior e recusado pelo destino, nao por nos.
    it 'refuses a name over 40 characters and accepts one with exactly 40' do
      expect(build_event(name: "chatspx_#{'a' * 32}")).to be_valid

      too_long = build_event(name: "chatspx_#{'a' * 33}")
      expect(too_long).not_to be_valid
      expect(too_long.errors[:name]).to eq(['passa do limite de 40 caracteres do GA4'])
    end
  end

  describe 'properties never carry raw PII (regra RC5)' do
    %w[em ph fn ln email phone phone_number first_name last_name].each do |key|
      it "refuses #{key} in properties, naming the key" do
        event = build_event(properties: { key => 'algum valor' })

        expect(event).not_to be_valid
        expect(event.errors[:properties])
          .to eq(["não aceita dado pessoal cru: a chave \"#{key}\" sai hasheada pelo servidor, nunca aqui"])
      end
    end

    it 'accepts properties that merely mention a person without carrying one' do
      expect(build_event(properties: { 'lead_source' => 'widget', 'filled_fields' => %w[email phone] })).to be_valid
    end

    it 'defaults properties to an empty hash' do
      event = build_event(properties: nil)
      event.save!

      expect(event.reload.properties).to eq({})
    end
  end

  describe 'defaults declared in the contract' do
    it 'defaults occurred_at to now and source to server' do
      event = described_class.new(name: 'chatspx_lead', account: account, dedup_key: 'fato-3')
      event.save!

      expect(event.reload.source).to eq('server')
      expect(event.occurred_at).to be_within(5.seconds).of(Time.current)
    end

    it 'derives dedup_key from the fact when the caller omits it' do
      moment = Time.zone.parse('2026-08-18 10:00:00')
      event = described_class.new(name: 'chatspx_conversation_resolved', account: account,
                                  conversation: conversation, occurred_at: moment)
      event.save!

      expect(event.reload.dedup_key).to eq("chatspx_conversation_resolved:#{conversation.id}:#{moment.to_i}")
    end

    it 'falls back to the contact and then to the account in the derived key' do
      contact = create(:contact, account: account)
      moment = Time.zone.parse('2026-08-18 10:00:00')

      with_contact = described_class.create!(name: 'chatspx_lead', account: account, contact: contact,
                                             occurred_at: moment)
      account_wide = described_class.create!(name: 'chatspx_deal_won', account: account, occurred_at: moment)

      expect(with_contact.dedup_key).to eq("chatspx_lead:#{contact.id}:#{moment.to_i}")
      expect(account_wide.dedup_key).to eq("chatspx_deal_won:account:#{moment.to_i}")
    end
  end

  describe 'the same fact recorded twice is one record (idempotencia do FATO)' do
    it 'refuses a second record with the same account, name and dedup_key' do
      build_event(dedup_key: 'conversation:9:resolved:1000').save!

      expect { build_event(dedup_key: 'conversation:9:resolved:1000').save! }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows the same dedup_key for a different event name' do
      build_event(dedup_key: 'mesma-chave').save!

      expect(build_event(name: 'chatspx_lead', dedup_key: 'mesma-chave').save).to be(true)
    end

    it 'allows the same dedup_key in another account' do
      build_event(dedup_key: 'mesma-chave').save!
      other = create(:account)

      expect(build_event(account: other, dedup_key: 'mesma-chave').save).to be(true)
    end
  end

  describe 'deleting the parent never fails, and the history survives' do
    it 'nullifies conversation_id instead of blocking conversation deletion' do
      event = build_event(inbox: inbox, conversation: conversation).tap(&:save!)

      expect { conversation.destroy! }.not_to raise_error
      expect(event.reload.conversation_id).to be_nil
      expect(event.reload.name).to eq('chatspx_conversation_resolved')
    end

    it 'nullifies contact_id instead of blocking contact deletion' do
      contact = create(:contact, account: account)
      event = build_event(contact: contact).tap(&:save!)

      expect { contact.destroy! }.not_to raise_error
      expect(event.reload.contact_id).to be_nil
    end

    it 'nullifies inbox_id instead of blocking inbox deletion' do
      event = build_event(inbox: inbox).tap(&:save!)

      expect { inbox.destroy! }.not_to raise_error
      expect(event.reload.inbox_id).to be_nil
    end
  end
end
