# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Contacts::ResolveLidSweepJob do
  let(:account) { create(:account) }
  let(:waha_inbox) { create(:inbox, account: account, waha_session_name: 'spx-test') }
  let(:non_waha_inbox) { create(:inbox, account: account) }

  describe '#perform' do
    it 'reenfileira ResolveLidJob (em :scheduled_jobs) para contact_inbox com source_id @lid' do
      contact = create(:contact, account: account)
      contact_inbox = create(:contact_inbox, contact: contact, inbox: waha_inbox, source_id: '123456@lid')

      expect { described_class.perform_now }
        .to have_enqueued_job(Contacts::ResolveLidJob).with(contact_inbox.id).on_queue('scheduled_jobs')
    end

    it 'reenfileira para contato com identifier @lid mesmo que o source_id ja esteja resolvido' do
      contact = create(:contact, account: account, identifier: '123456@lid')
      contact_inbox = create(:contact_inbox, contact: contact, inbox: waha_inbox, source_id: '5511999999999@c.us')

      expect { described_class.perform_now }
        .to have_enqueued_job(Contacts::ResolveLidJob).with(contact_inbox.id)
    end

    it 'reenfileira para contato com name @lid' do
      contact = create(:contact, account: account, name: '123456@lid')
      contact_inbox = create(:contact_inbox, contact: contact, inbox: waha_inbox, source_id: '5511999999999@c.us')

      expect { described_class.perform_now }
        .to have_enqueued_job(Contacts::ResolveLidJob).with(contact_inbox.id)
    end

    it 'NAO reenfileira para inbox sem waha_session_name (onde o job seria no-op)' do
      contact = create(:contact, account: account)
      create(:contact_inbox, contact: contact, inbox: non_waha_inbox, source_id: '123456@lid')

      expect { described_class.perform_now }.not_to have_enqueued_job(Contacts::ResolveLidJob)
    end

    it 'respeita o teto por execucao (max_per_run)' do
      3.times do |i|
        contact = create(:contact, account: account)
        create(:contact_inbox, contact: contact, inbox: waha_inbox, source_id: "#{i}00000@lid")
      end

      expect { described_class.perform_now(2) }
        .to have_enqueued_job(Contacts::ResolveLidJob).exactly(2).times
    end

    it 'e no-op quando nao ha @lid preso' do
      create(:contact_inbox, contact: create(:contact, account: account), inbox: waha_inbox, source_id: '5511999999999@c.us')

      expect { described_class.perform_now }.not_to have_enqueued_job(Contacts::ResolveLidJob)
    end
  end
end
