# frozen_string_literal: true

require 'rails_helper'

# Pedido de aprovação/ajuda no chat interno: quem pode decidir e o que muda.
RSpec.describe 'Chat interno: pedido de aprovação/ajuda', type: :request do
  let(:account) { create(:account).tap { |acc| acc.enable_features!('internal_chat') } }
  let(:alice) { create(:user, account: account, role: :agent) }
  let(:boss) { create(:user, account: account, role: :administrator) }
  let(:carol) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:internal_channel, :group_chat, :with_two_members, account: account, user_a: alice, user_b: boss).tap do |c|
      create(:internal_channel_member, internal_channel: c, user: carol)
    end
  end
  let(:base) { "/api/v1/accounts/#{account.id}/internal_channels/#{channel.id}/internal_messages" }

  def create_request(kind:, approver: boss)
    post base, params: { request: { kind: kind, title: 'Desconto de 5%', detail: 'apto 2 dorm', approver_id: approver&.id } },
               headers: alice.create_new_auth_token, as: :json
    InternalMessage.find_by(id: response.parsed_body['id'])
  end

  def decide(message, user, decision, reason: nil)
    post "#{base}/#{message.id}/decide", params: { decision: decision, reason: reason },
                                         headers: user.create_new_auth_token, as: :json
  end

  it 'creates an approval request addressed to a member and mentions the approver' do
    message = create_request(kind: 'approval')
    expect(response).to have_http_status(:created)
    expect(message).to be_message_type_request
    expect(message.content).to eq('Desconto de 5%')
    expect(message.request_data).to include('kind' => 'approval', 'approver_id' => boss.id, 'status' => 'pending')
    expect(message.mentioned_user_ids).to eq([boss.id])
  end

  it 'rejects an approval without an approver from the channel' do
    outsider = create(:user, account: account, role: :administrator)
    create_request(kind: 'approval', approver: outsider)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'only the approver can approve, and only once' do
    message = create_request(kind: 'approval')

    decide(message, carol, 'approve')
    expect(response).to have_http_status(:forbidden)
    decide(message, alice, 'approve')
    expect(response).to have_http_status(:forbidden)

    expect { decide(message, boss, 'approve') }
      .to have_enqueued_job(ActionCableBroadcastJob)
      .with(anything, 'internal.message.updated', hash_including(notice: a_string_including(boss.name)))
    expect(response).to have_http_status(:success)
    expect(message.reload.request_data).to include('status' => 'approved', 'decided_by_id' => boss.id)

    decide(message, boss, 'deny')
    expect(response).to have_http_status(:conflict)
  end

  it 'keeps the reason when the approver declines' do
    message = create_request(kind: 'approval')
    decide(message, boss, 'deny', reason: 'acima da alçada')
    expect(message.reload.request_data).to include('status' => 'denied', 'reason' => 'acima da alçada')
  end

  it 'lets any other member take a help request, but not the requester' do
    message = create_request(kind: 'help', approver: nil)
    decide(message, alice, 'help')
    expect(response).to have_http_status(:forbidden)
    decide(message, carol, 'approve')
    expect(response).to have_http_status(:forbidden)

    decide(message, carol, 'help')
    expect(message.reload.request_data).to include('status' => 'taken', 'decided_by_name' => carol.name)
  end

  it 'does not allow editing a request' do
    message = create_request(kind: 'approval')
    patch "#{base}/#{message.id}", params: { content: 'outro' }, headers: alice.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
