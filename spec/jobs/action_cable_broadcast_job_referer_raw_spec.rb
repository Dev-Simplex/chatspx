require 'rails_helper'

# Bloco 1.20, asserção (5) — a metade que decide ONDE o filtro tem de morar.
#
# O `ActionCableBroadcastJob#prepare_broadcast_data` REMONTA o payload a partir do banco para os
# eventos de conversa. Quer dizer: filtrar `referer_raw` no listener seria inútil para
# CONVERSATION_UPDATED / CONVERSATION_STATUS_CHANGED — o job descartaria o payload filtrado e o
# reconstruiria com `conversation.push_event_data`, trazendo o campo de volta. Por isso o filtro
# vive no `Conversations::EventDataPresenter`, e é aqui que isso fica medido.
#
# O primeiro exemplo é o controle positivo do remontador: sem ele, o segundo passaria mesmo se o
# job só repassasse o payload já filtrado pelo listener, e não mediria a remontagem.
RSpec.describe ActionCableBroadcastJob do
  let(:raw_visitor_url) { 'javascript:alert(document.cookie)' }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) do
    create(:conversation,
           account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
           status: :open,
           additional_attributes: { 'referer' => raw_visitor_url, 'browser_language' => 'pt-BR' })
  end

  # O que ActionCable.server.broadcast recebeu de verdade: [member, envelope].
  let(:delivered) { [] }

  before do
    allow(ActionCable.server).to receive(:broadcast) { |member, data| delivered << [member, data] }
  end

  it 'ignora o payload recebido e remonta do banco (controle positivo do remontador)' do
    lying_payload = conversation.push_event_data.merge(account_id: account.id, status: 'resolved')

    described_class.perform_now([contact_inbox.pubsub_token], 'conversation.updated', lying_payload)

    _member, envelope = delivered.last
    # Se o job apenas repassasse, sairia 'resolved'. Sai 'open' porque ele releu do banco.
    expect(envelope[:data][:status]).to eq('open')
  end

  it 'não entrega referer_raw ao token do contact_inbox' do
    # Controle positivo: existe algo para vazar.
    expect(conversation.reload.additional_attributes['referer_raw']).to eq(raw_visitor_url)

    described_class.perform_now([contact_inbox.pubsub_token], 'conversation.updated',
                                conversation.push_event_data.merge(account_id: account.id))

    member, envelope = delivered.last
    expect(member).to eq(contact_inbox.pubsub_token)
    expect(envelope[:data][:additional_attributes]).not_to have_key('referer_raw')
    expect(envelope.to_json).not_to include('referer_raw')
    expect(envelope.to_json).not_to include('alert(document.cookie)')
  end

  it 'preserva o resto de additional_attributes no payload remontado' do
    described_class.perform_now([contact_inbox.pubsub_token], 'conversation.updated',
                                conversation.push_event_data.merge(account_id: account.id))

    _member, envelope = delivered.last
    expect(envelope[:data][:additional_attributes]['browser_language']).to eq('pt-BR')
  end
end
