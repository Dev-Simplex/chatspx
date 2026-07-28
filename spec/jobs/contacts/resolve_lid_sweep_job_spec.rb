# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Contacts::ResolveLidSweepJob do
  let(:account) { create(:account) }
  let(:waha_inbox) { create(:inbox, account: account, waha_session_name: 'spx-test') }
  let(:non_waha_inbox) { create(:inbox, account: account) }
  let(:sessions_url) { 'https://waha.example.com/api/sessions?all=true' }

  before do
    stub_const('ENV', ENV.to_h.merge('WAHA_API_URL' => 'https://waha.example.com', 'WAHA_API_KEY' => 'k'))
    # O sweep passou a checar o status da sessao antes de enfileirar (issue 27).
    stub_request(:get, sessions_url).to_return(
      status: 200,
      body: [{ 'name' => 'spx-test', 'status' => 'WORKING' }, { 'name' => 'morta', 'status' => 'FAILED' }].to_json
    )
    Waha::SessionStatusCache.reset!
  end

  after { Waha::SessionStatusCache.reset! }

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

  # Regressao da issue 27 do GlitchTip: UM contact_inbox apontando para sessao FAILED
  # gerou 2.812 Net::ReadTimeout em 20 dias porque o sweep o reenfileirava 7x/h.
  describe 'guarda de sessao' do
    let(:dead_inbox) { create(:inbox, account: account, waha_session_name: 'morta') }

    it 'NAO reenfileira quando a sessao da caixa nao esta WORKING' do
      contact = create(:contact, account: account)
      create(:contact_inbox, contact: contact, inbox: dead_inbox, source_id: '81820414494285957058@lid')

      expect { described_class.perform_now }.not_to have_enqueued_job(Contacts::ResolveLidJob)
    end

    it 'NAO reenfileira quando a sessao nem existe mais na WAHA' do
      ghost_inbox = create(:inbox, account: account, waha_session_name: 'spx')
      contact = create(:contact, account: account)
      create(:contact_inbox, contact: contact, inbox: ghost_inbox, source_id: '123456@lid')

      expect { described_class.perform_now }.not_to have_enqueued_job(Contacts::ResolveLidJob)
    end

    it 'gasta UMA chamada a /api/sessions para a execucao inteira, nao uma por contato' do
      3.times do |i|
        create(:contact_inbox, contact: create(:contact, account: account), inbox: waha_inbox, source_id: "#{i}00000@lid")
      end

      described_class.perform_now

      expect(a_request(:get, sessions_url)).to have_been_made.once
    end

    it 'segue enfileirando (fail-open) quando nao da para saber o status na WAHA' do
      stub_request(:get, sessions_url).to_return(status: 500, body: 'boom')
      contact = create(:contact, account: account)
      contact_inbox = create(:contact_inbox, contact: contact, inbox: waha_inbox, source_id: '123456@lid')

      expect { described_class.perform_now }
        .to have_enqueued_job(Contacts::ResolveLidJob).with(contact_inbox.id)
    end
  end

  describe 'memoria de falha (backoff)' do
    let(:lid) { '81820414494285957058@lid' }

    after { Whatsapp::LidPhoneCache.clear_failures('spx-test', lid) }

    it 'NAO reenfileira LID em backoff' do
      contact = create(:contact, account: account)
      create(:contact_inbox, contact: contact, inbox: waha_inbox, source_id: lid)
      Whatsapp::LidPhoneCache.record_failure('spx-test', lid)

      expect { described_class.perform_now }.not_to have_enqueued_job(Contacts::ResolveLidJob)
    end

    it 'volta a reenfileirar quando o backoff e limpo (LID resolvido em outro caminho)' do
      contact = create(:contact, account: account)
      contact_inbox = create(:contact_inbox, contact: contact, inbox: waha_inbox, source_id: lid)
      Whatsapp::LidPhoneCache.record_failure('spx-test', lid)
      Whatsapp::LidPhoneCache.clear_failures('spx-test', lid)

      expect { described_class.perform_now }
        .to have_enqueued_job(Contacts::ResolveLidJob).with(contact_inbox.id)
    end

    it 'usa o identifier do contato como LID quando o source_id ja foi normalizado' do
      contact = create(:contact, account: account, identifier: lid)
      create(:contact_inbox, contact: contact, inbox: waha_inbox, source_id: '5511999999999@c.us')
      Whatsapp::LidPhoneCache.record_failure('spx-test', lid)

      expect { described_class.perform_now }.not_to have_enqueued_job(Contacts::ResolveLidJob)
    end
  end
end
