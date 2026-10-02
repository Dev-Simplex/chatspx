require 'rails_helper'

# Reconciliação do Captador (22 §1.5): estado das conversas por lead e por contato, desde um instante.
RSpec.describe 'Spx::Captador::Conversas', type: :request do
  include CaptadorSigningHelpers

  let(:account) { create(:account) }
  let!(:hook) { captador_hook_for(account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:lead_contact) { create(:contact, account: account) }
  let(:returning_contact) { create(:contact, account: account, custom_attributes: { 'captador_lead_id' => 'lead-2' }) }
  let!(:lead_conversation) do
    create(:inbox_member, inbox: inbox, user: agent)
    create(:conversation, account: account, inbox: inbox, contact: lead_contact, assignee: agent,
                          custom_attributes: { 'captador_lead_id' => 'lead-1' })
  end
  let!(:returning_conversation) { create(:conversation, account: account, inbox: inbox, contact: returning_contact) }
  let!(:incoming) { create(:message, account: account, inbox: inbox, conversation: lead_conversation, message_type: :incoming) }
  let!(:opening) do
    create(:message, account: account, inbox: inbox, conversation: lead_conversation, message_type: :outgoing, status: :failed,
                     additional_attributes: { 'echo_id' => 'captador:envio-1' },
                     content_attributes: { 'external_error' => '131026: Message undeliverable' })
  end

  def reconcile(query)
    captador_get("/spx/captador/v1/conversas?#{query}", hook: hook)
    response.parsed_body
  end

  it 'devolve o estado das conversas por lead e por contato' do
    body = reconcile("lead_ids=lead-1&contact_ids=#{returning_contact.id}")

    expect(response).to have_http_status(:ok)
    expect(body['server_time']).to be_present
    by_id = body['conversations'].index_by { |conversation| conversation['conversation_id'] }
    expect(by_id.keys).to contain_exactly(lead_conversation.display_id, returning_conversation.display_id)

    lead = by_id[lead_conversation.display_id]
    expect(lead).to include('lead_id' => 'lead-1', 'contact_id' => lead_contact.id, 'inbox_id' => inbox.id, 'status' => 'open',
                            'assignee' => { 'id' => agent.id, 'name' => agent.available_name }, 'team' => nil, 'opt_out' => false)
    expect(lead['last_incoming_at']).to be_present
    expect(lead['captador_message']).to include('id' => opening.id, 'status' => 'failed', 'external_error' => '131026: Message undeliverable')

    # Conversa nova do mesmo contato, sem o carimbo: o lead vem do contato.
    expect(by_id[returning_conversation.display_id]).to include('lead_id' => 'lead-2', 'captador_message' => nil)
  end

  it 'marca opt_out do contato suprimido para marketing' do
    ContactFlowSuppression.record_opt_out!(contact: lead_contact, account: account)

    expect(reconcile('lead_ids=lead-1')['conversations'].first['opt_out']).to be(true)
  end

  it 'com since, só devolve o que mudou depois do instante (inclusive status de mensagem)' do
    lead_conversation.update_columns(updated_at: 2.days.ago, last_activity_at: 2.days.ago) # rubocop:disable Rails/SkipsModelValidations
    lead_conversation.messages.update_all(updated_at: 2.days.ago) # rubocop:disable Rails/SkipsModelValidations

    expect(reconcile("lead_ids=lead-1&since=#{1.day.ago.utc.iso8601}")['conversations']).to be_empty

    opening.update!(status: :delivered)
    ids = reconcile("lead_ids=lead-1&since=#{1.day.ago.to_i}")['conversations'].pluck('conversation_id')
    expect(ids).to eq([lead_conversation.display_id])
  end

  it 'não mistura conversas de outra conta' do
    other_account = create(:account)
    create(:conversation, account: other_account, inbox: create(:inbox, account: other_account),
                          custom_attributes: { 'captador_lead_id' => 'lead-1' })

    expect(reconcile('lead_ids=lead-1')['conversations'].size).to eq(1)
  end

  it 'valida os parâmetros' do
    reconcile('since=2026-01-01T00:00:00Z')
    expect(response.parsed_body['error_code']).to eq('ids_required')

    reconcile("lead_ids=#{(1..101).map { |i| "l#{i}" }.join(',')}")
    expect(response.parsed_body['error_code']).to eq('too_many_ids')

    reconcile('lead_ids=lead-1&since=ontem')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error_code']).to eq('invalid_since')
  end
end
