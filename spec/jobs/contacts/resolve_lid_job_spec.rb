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

  # Contexto: GlitchTip issue 27 — 2.812 Net::ReadTimeout em 20 dias, todos de UM
  # contact_inbox apontando para sessao FAILED. A WAHA leva ~10s para dizer 422 e o
  # timeout do ApiService e 8s, entao o erro tratavel nunca chega.
  describe 'freios antes da chamada a WAHA' do
    let(:lid) { '81820414494285957058@lid' }
    let(:session) { 'spx-test' }
    let(:sessions_url) { 'https://waha.example.com/api/sessions?all=true' }
    let(:lid_url) { "https://waha.example.com/api/#{session}/lids/#{URI.encode_www_form_component(lid)}" }
    let(:lids_list_url) { "https://waha.example.com/api/#{session}/lids?limit=500&offset=0" }
    # Sem waha_whatsapp_jid: forca o caminho cache/WAHA.
    let!(:lid_contact) do
      create(:contact, account: account, name: lid, identifier: lid, phone_number: nil)
    end
    let!(:lid_contact_inbox) do
      create(:contact_inbox, contact: lid_contact, inbox: inbox, source_id: lid)
    end

    before do
      stub_const('ENV', ENV.to_h.merge('WAHA_API_URL' => 'https://waha.example.com', 'WAHA_API_KEY' => 'k'))
      stub_request(:get, sessions_url).to_return(
        status: 200,
        body: [{ 'name' => session, 'status' => 'WORKING' }].to_json
      )
      Waha::SessionStatusCache.reset!
      Whatsapp::LidPhoneCache.clear_failures(session, lid)
      Redis::Alfred.delete(Whatsapp::LidPhoneCache.key(session, lid))
    end

    after do
      Waha::SessionStatusCache.reset!
      Whatsapp::LidPhoneCache.clear_failures(session, lid)
      Redis::Alfred.delete(Whatsapp::LidPhoneCache.key(session, lid))
    end

    context 'with a warm LID->PN cache' do
      before { Whatsapp::LidPhoneCache.write(session, lid, '5511999999999') }

      it 'resolve pelo cache sem tocar na WAHA' do
        lid_stub = stub_request(:get, lid_url)

        described_class.perform_now(lid_contact_inbox.id)

        expect(lid_stub).not_to have_been_requested
        expect(lid_contact.reload.phone_number).to eq(normalized_phone)
      end

      it 'reconstroi o JID a partir dos digitos do cache (source_id nao pode virar so numero)' do
        stub_request(:get, lid_url)

        described_class.perform_now(lid_contact_inbox.id)

        expect(lid_contact_inbox.reload.source_id).to eq(resolved_jid)
      end
    end

    context 'when the inbox session is not WORKING' do
      before do
        stub_request(:get, sessions_url).to_return(
          status: 200, body: [{ 'name' => 'outra', 'status' => 'WORKING' }, { 'name' => session, 'status' => 'FAILED' }].to_json
        )
        Waha::SessionStatusCache.reset!
      end

      it 'nao bate na WAHA nem levanta (era o que queimava as 7 tentativas)' do
        lid_stub = stub_request(:get, lid_url)

        expect { described_class.perform_now(lid_contact_inbox.id) }.not_to raise_error
        expect(lid_stub).not_to have_been_requested
      end

      it 'nao conta como falha do LID — a culpa e da sessao, nao dele' do
        described_class.perform_now(lid_contact_inbox.id)

        expect(Whatsapp::LidPhoneCache.failure_count(session, lid)).to eq(0)
      end
    end

    context 'when the LID is in backoff' do
      before { Whatsapp::LidPhoneCache.record_failure(session, lid) }

      it 'nao bate na WAHA nem levanta' do
        lid_stub = stub_request(:get, lid_url)

        expect { described_class.perform_now(lid_contact_inbox.id) }.not_to raise_error
        expect(lid_stub).not_to have_been_requested
      end
    end

    context 'when WAHA answers but does not know the LID' do
      before do
        stub_request(:get, lid_url).to_return(status: 200, body: { 'lid' => lid, 'pn' => nil }.to_json)
        stub_request(:get, lids_list_url).to_return(status: 200, body: [].to_json)
      end

      # LidNotResolvable e capturado pelo `retry_on` da classe, entao `perform_now`
      # nao propaga: o sinal observavel e o reagendamento.
      it 'registra o ciclo falho e abre o backoff' do
        expect { described_class.perform_now(lid_contact_inbox.id) }.to have_enqueued_job(described_class)

        expect(Whatsapp::LidPhoneCache.failure_count(session, lid)).to eq(1)
        expect(Whatsapp::LidPhoneCache).to be_cooling_down(session, lid)
      end

      it 'grava o cache negativo curto para a ingestao de mensagem tambem parar de tentar' do
        described_class.perform_now(lid_contact_inbox.id)

        expect(Whatsapp::LidPhoneCache).to be_unresolved(session, lid)
      end

      # Sem este freio, as 7 tentativas de um unico ciclo levariam o LID direto ao
      # teto de 7 dias do backoff — perdendo toda a gradacao.
      it 'conta UM ciclo, nao uma falha por retry' do
        job = described_class.new(lid_contact_inbox.id)
        job.executions = 3
        job.perform_now

        expect(Whatsapp::LidPhoneCache.failure_count(session, lid)).to eq(0)
      end
    end

    context 'when WAHA resolves the LID' do
      before do
        Whatsapp::LidPhoneCache.record_failure(session, lid)
        Whatsapp::LidPhoneCache.clear_failures(session, lid) # limpa o cooldown, mantem o cenario "veio da WAHA"
        stub_request(:get, lid_url).to_return(status: 200, body: { 'lid' => lid, 'pn' => resolved_jid }.to_json)
      end

      it 'popula o cache com o telefone resolvido' do
        described_class.perform_now(lid_contact_inbox.id)

        expect(Whatsapp::LidPhoneCache.phone(session, lid)).to eq('5511999999999')
      end

      it 'zera a memoria de falha' do
        described_class.perform_now(lid_contact_inbox.id)

        expect(Whatsapp::LidPhoneCache.failure_count(session, lid)).to eq(0)
        expect(Whatsapp::LidPhoneCache).not_to be_cooling_down(session, lid)
      end
    end
  end
end
