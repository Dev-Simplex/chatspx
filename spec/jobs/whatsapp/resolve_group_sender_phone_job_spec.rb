require 'rails_helper'

RSpec.describe Whatsapp::ResolveGroupSenderPhoneJob do
  subject(:job) { described_class }

  let(:session_name) { 'Simplex' }
  let(:lid) { '229480102662169' }
  let!(:api_channel) { create(:channel_api) }
  let(:inbox) { api_channel.inbox }
  let(:contact) { create(:contact, account: api_channel.account, identifier: '556699999999-1634750731@g.us') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, contact: contact, contact_inbox: contact_inbox, inbox: inbox) }
  let(:message) do
    create(:message, account: conversation.account, inbox: inbox, conversation: conversation,
                     content: 'Qual Wi-Fi está?',
                     content_attributes: { 'group_sender' => { 'name' => 'Rogerio', 'lid' => lid, 'phone' => nil } })
  end
  let(:waha_service) { instance_double(Waha::ApiService) }

  # Cache, circuito e lock da listagem sobrevivem ao rollback do banco — limpar
  # dos dois lados evita suite intermitente com a ordem aleatoria do RSpec.
  def clear_redis_keys
    Redis::Alfred.delete(Whatsapp::LidPhoneCache.key(session_name, lid))
    Redis::Alfred.delete("#{Whatsapp::GroupSenderPhoneResolver::CIRCUIT_KEY}:#{session_name}")
    Redis::Alfred.delete("#{Whatsapp::GroupSenderPhoneResolver::LIST_LOCK_KEY}:#{session_name}")
  end

  before do
    inbox.update!(waha_session_name: session_name)
    allow(Waha::ApiService).to receive(:new).and_return(waha_service)
    clear_redis_keys
  end

  after { clear_redis_keys }

  it 'grava o telefone resolvido no group_sender' do
    allow(waha_service).to receive(:get_lid_phone_number).and_return('pn' => '5566999991234@c.us')

    job.perform_now(message.id)

    expect(message.reload.content_attributes['group_sender']).to eq(
      'name' => 'Rogerio', 'lid' => lid, 'phone' => '5566999991234'
    )
  end

  it 'nao toca na mensagem quando a WAHA nao resolve' do
    allow(waha_service).to receive(:get_lid_phone_number).and_return('pn' => nil)
    allow(waha_service).to receive(:get_lids_list).and_return([])

    expect { job.perform_now(message.id) }.not_to(change { message.reload.content_attributes })
  end

  it 'reagenda com backoff quando a WAHA esta fora, sem estourar' do
    allow(waha_service).to receive(:get_lid_phone_number).and_raise(Waha::ApiService::ConnectionError, 'timeout')

    expect { job.perform_now(message.id) }.to have_enqueued_job(described_class)
    expect(message.reload.content_attributes['group_sender']['phone']).to be_nil
  end

  it 'nao reagenda quando a sessao nao existe na WAHA' do
    allow(waha_service).to receive(:get_lid_phone_number).and_raise(Waha::ApiService::NotFoundError, 'Session not found')

    expect { job.perform_now(message.id) }.not_to have_enqueued_job(described_class)
    expect(Whatsapp::LidPhoneCache).to be_unresolved(session_name, lid)
  end

  it 'ignora mensagem sem group_sender' do
    plain = create(:message, account: conversation.account, inbox: inbox, conversation: conversation, content: 'oi')

    expect(waha_service).not_to receive(:get_lid_phone_number)
    expect { job.perform_now(plain.id) }.not_to raise_error
  end

  it 'ignora mensagem cujo telefone ja foi resolvido' do
    message.update!(content_attributes: { 'group_sender' => { 'name' => 'Rogerio', 'lid' => lid, 'phone' => '5566999991234' } })

    expect(waha_service).not_to receive(:get_lid_phone_number)
    job.perform_now(message.id)
  end

  it 'ignora inbox sem sessao WAHA' do
    inbox.update!(waha_session_name: nil)

    expect(waha_service).not_to receive(:get_lid_phone_number)
    job.perform_now(message.id)
  end

  it 'ignora mensagem que sumiu' do
    expect { job.perform_now(0) }.not_to raise_error
  end
end
