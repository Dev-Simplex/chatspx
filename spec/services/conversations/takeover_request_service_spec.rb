require 'rails_helper'

RSpec.describe Conversations::TakeoverRequestService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:owner) { create(:user, account: account, role: :agent) }
  let(:requester) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: owner, status: :open) }

  # O create! agora exige o modo ligado (guard de backend); o resto do fluxo
  # assume Fase 3 ON. Um teste dedicado cobre o OFF.
  before { account.update!(takeover_request_gate: true) }

  describe '#create!' do
    it 'snapshots the current owner into owner_id' do
      request = described_class.new(conversation: conversation, actor: requester).create!(reason: 'preciso')

      expect(request.owner_id).to eq(owner.id)
      expect(request.requester_id).to eq(requester.id)
      expect(request).to be_pending
      expect(request.reason).to eq('preciso')
    end

    it 'refuses to create when the takeover mode is off' do
      account.update!(takeover_request_gate: false)
      expect { described_class.new(conversation: conversation, actor: requester).create! }
        .to raise_error(described_class::Error) { |e| expect(e.error_code).to eq(:takeover_gate_disabled) }
      expect(ConversationTakeoverRequest.count).to eq(0)
    end

    it 'refuses a conversation with no owner' do
      unowned = create(:conversation, account: account, inbox: inbox, assignee: nil, status: :open)
      expect { described_class.new(conversation: unowned, actor: requester).create! }
        .to raise_error(described_class::Error) { |e| expect(e.error_code).to eq(:conversation_unassigned) }
    end

    it 'refuses a conversation owned by an AI bot with the right error' do
      bot_conv = create(:conversation, account: account, inbox: inbox, assignee: nil, status: :open)
      assistant = create(:captain_assistant, account: account)
      bot_conv.update!(assignee_agent_bot: assistant.mirror_agent_bot)

      expect { described_class.new(conversation: bot_conv, actor: requester).create! }
        .to raise_error(described_class::Error) { |e| expect(e.error_code).to eq(:conversation_owned_by_bot) }
    end

    # Índice único parcial: o MESMO agente não pede 2x.
    it 'refuses a second pending request from the same requester' do
      described_class.new(conversation: conversation, actor: requester).create!
      expect { described_class.new(conversation: conversation, actor: requester).create! }
        .to raise_error(described_class::Error) { |e| expect(e.error_code).to eq(:takeover_request_exists) }
    end

    it 'allows a DIFFERENT agent to request the same conversation' do
      other = create(:user, account: account, role: :agent)
      described_class.new(conversation: conversation, actor: requester).create!
      expect { described_class.new(conversation: conversation, actor: other).create! }.not_to raise_error
    end

    it 'allows a new request after the previous one was cancelled' do
      first = described_class.new(conversation: conversation, actor: requester).create!
      described_class.new(request: first, actor: requester).cancel!
      expect { described_class.new(conversation: conversation, actor: requester).create! }.not_to raise_error
    end
  end

  describe '#approve!' do
    let(:request) { described_class.new(conversation: conversation, actor: requester).create! }

    it 'assigns the conversation to the requester' do
      described_class.new(request: request, actor: owner).approve!

      expect(conversation.reload.assignee_id).to eq(requester.id)
      expect(request.reload).to be_approved
      expect(request.resolution_source).to eq('owner')
    end

    # Regressão clássica: o próprio caminho de aprovação NÃO pode ser barrado
    # pelo gate. Com o gate LIGADO, aprovar tem que funcionar.
    it 'approves even with the takeover gate enabled' do
      account.update!(settings: account.settings.merge('takeover_request_gate' => true))
      described_class.new(request: request, actor: owner).approve!
      expect(conversation.reload.assignee_id).to eq(requester.id)
    end

    it 'leaves the thread-local flag clean afterwards (no leak between requests)' do
      described_class.new(request: request, actor: owner).approve!
      expect(Current.takeover_approval_in_progress).to be_nil
    end

    it 'raises stale when the conversation changed owner since the request' do
      third = create(:user, account: account, role: :agent)
      conversation.update!(assignee: third) # muda de mãos por outro caminho...
      request # ...só que o pedido guardou owner=owner

      # o supersede automático já fecha o pedido; forço um pending "velho" p/ testar o guard do approve
      request.update_columns(status: 0, owner_id: owner.id) # rubocop:disable Rails/SkipsModelValidations
      expect { described_class.new(request: request.reload, actor: owner).approve! }
        .to raise_error(described_class::Error) { |e| expect(e.error_code).to eq(:takeover_request_stale) }
    end

    it 'raises closed when approving twice' do
      described_class.new(request: request, actor: owner).approve!
      expect { described_class.new(request: request.reload, actor: owner).approve! }
        .to raise_error(described_class::Error) { |e| expect(e.error_code).to eq(:takeover_request_closed) }
    end

    # Dois agentes pedem; aprovar um supersede o outro na MESMA transação.
    it 'supersedes sibling requests when one is approved' do
      other = create(:user, account: account, role: :agent)
      sibling = described_class.new(conversation: conversation, actor: other).create!

      described_class.new(request: request, actor: owner).approve!

      expect(sibling.reload).to be_superseded
      expect(sibling.resolution_source).to eq('system')
    end

    # ...e o solicitante PERDEDOR recebe o sinal realtime (senão fica preso em
    # "Pedido enviado" até um refetch manual).
    it 'broadcasts the supersede to the losing requester' do
      other = create(:user, account: account, role: :agent)
      sibling = described_class.new(conversation: conversation, actor: other).create!

      expect do
        described_class.new(request: request, actor: owner).approve!
      end.to have_enqueued_job(ActionCableBroadcastJob)
        .with([other.pubsub_token], 'takeover_request.updated', hash_including(id: sibling.id, status: 'superseded'))
    end

    it 'records admin as the resolution source when an admin approves' do
      described_class.new(request: request, actor: admin).approve!
      expect(request.reload.resolution_source).to eq('admin')
    end
  end

  describe '#deny!' do
    it 'denies without transferring' do
      request = described_class.new(conversation: conversation, actor: requester).create!
      described_class.new(request: request, actor: owner).deny!(note: 'agora não')

      expect(request.reload).to be_denied
      expect(conversation.reload.assignee_id).to eq(owner.id)
    end
  end

  describe 'edge cases' do
    it 'supersedes pending requests when the conversation is reassigned by another path' do
      request = described_class.new(conversation: conversation, actor: requester).create!
      third = create(:user, account: account, role: :agent)

      conversation.update!(assignee: third)

      expect(request.reload).to be_superseded
    end

    # Exceção: o novo dono É o solicitante → aprovado/system, não superseded.
    it 'approves the request when the new owner is the requester' do
      request = described_class.new(conversation: conversation, actor: requester).create!

      conversation.update!(assignee: requester)

      expect(request.reload).to be_approved
      expect(request.resolution_source).to eq('system')
    end

    it 'supersedes pending requests when the owner leaves the account' do
      request = described_class.new(conversation: conversation, actor: requester).create!

      Agents::DestroyJob.perform_now(account.id, owner.id)

      expect(request.reload).to be_superseded
    end
  end
end
