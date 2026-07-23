require 'rails_helper'

# rubocop:disable RSpec/MultipleDescribes, RSpec/DescribeClass
# Três grupos de propósito: o PORO, as 3 superfícies humanas e as regressões que
# o guard NÃO pode quebrar. Aninhar misturaria unidade com request spec.

# D1 — "o pedido é o único caminho". Este arquivo cobre as DUAS metades:
#   1. o que a trava PROMETE (barra a tomada silenciosa)
#   2. o que a trava NÃO PODE QUEBRAR (automação, macro, round-robin, IA, admin)
# A segunda metade é a mais importante: um guard no lugar errado quebraria toda
# macro com assign_agent em silêncio.
RSpec.describe Conversations::TakeoverGate do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:owner) { create(:user, account: account, role: :agent) }
  let(:intruder) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: owner, status: :open) }

  def gate(conv: conversation, actor: intruder, new_assignee_id: nil)
    described_class.new(conversation: conv, actor: actor, new_assignee_id: new_assignee_id || actor&.id)
  end

  describe 'com o gate DESLIGADO (o padrão)' do
    # O modo nasce OFF: quem não ligar não pode ver diferença nenhuma.
    it 'never blocks' do
      expect(gate.blocked?).to be(false)
    end
  end

  describe 'com o gate LIGADO' do
    before { account.update!(settings: account.settings.merge('takeover_request_gate' => true)) }

    it 'blocks an agent taking a conversation owned by someone else' do
      expect(gate.blocked?).to be(true)
    end

    it 'lets an admin through (D3: admin força)' do
      expect(gate(actor: admin).blocked?).to be(false)
    end

    it 'lets the owner act on their own conversation' do
      expect(gate(actor: owner).blocked?).to be(false)
    end

    it 'lets anyone self-assign a conversation with no owner' do
      unowned = create(:conversation, account: account, inbox: inbox, assignee: nil, status: :open)
      expect(gate(conv: unowned).blocked?).to be(false)
    end

    it 'does not block when the conversation is owned by an AI mirror' do
      assistant = create(:captain_assistant, account: account)
      bot_owned = create(:conversation, account: account, inbox: inbox, assignee: nil, status: :open)
      bot_owned.update!(assignee_agent_bot: assistant.mirror_agent_bot)
      expect(gate(conv: bot_owned).blocked?).to be(false)
    end

    it 'does not block a no-op (assigning the owner to themselves again)' do
      expect(gate(actor: intruder, new_assignee_id: owner.id).blocked?).to be(false)
    end

    # Automação/round-robin chegam sem User; AgentBot-token chega como AgentBot.
    it 'does not block a non-human actor' do
      expect(gate(actor: nil).blocked?).to be(false)
      expect(gate(actor: create(:agent_bot)).blocked?).to be(false)
    end

    # Sem isto, aprovar um pedido seria impossível: o próprio caminho de
    # aprovação bateria no guard.
    it 'does not block while an approval is in progress' do
      Current.takeover_approval_in_progress = true
      expect(gate.blocked?).to be(false)
    ensure
      Current.takeover_approval_in_progress = nil
    end
  end
end

RSpec.describe 'D1 nas 3 superfícies humanas', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:owner) { create(:user, account: account, role: :agent) }
  let(:intruder) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: owner, status: :open) }

  before do
    create(:inbox_member, user: owner, inbox: inbox)
    create(:inbox_member, user: intruder, inbox: inbox)
  end

  def enable_gate!
    account.update!(settings: account.settings.merge('takeover_request_gate' => true))
  end

  describe '(a) assignments_controller' do
    it 'returns 422 AND leaves the assignee untouched' do
      enable_gate!
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/assignments",
           params: { assignee_id: intruder.id }, headers: intruder.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error_code']).to eq('takeover_request_required')
      expect(response.parsed_body['meta']['current_assignee']['id']).to eq(owner.id)
      # As duas coisas: 422 sem checar o efeito já passou verde em código quebrado.
      expect(conversation.reload.assignee_id).to eq(owner.id)
    end

    it 'assigns normally with the gate OFF' do
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/assignments",
           params: { assignee_id: intruder.id }, headers: intruder.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.reload.assignee_id).to eq(intruder.id)
    end

    it 'lets an admin force the assignment with the gate ON' do
      enable_gate!
      admin = create(:user, account: account, role: :administrator)
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/assignments",
           params: { assignee_id: admin.id }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.reload.assignee_id).to eq(admin.id)
    end
  end

  # O mais fácil de esquecer e o mais importante: hoje quem reabre a conversa
  # resolvida de um colega ROUBA a conversa, e nenhum teste percebia.
  describe '(c) toggle_status_service — o "quem reabre, assume"' do
    let(:resolved) { create(:conversation, account: account, inbox: inbox, assignee: owner, status: :resolved) }

    # Current.account é OBRIGATÓRIO aqui: User#agent? resolve via
    # current_account_user, que só existe com Current.account setado
    # (user_attribute_helpers.rb:24). Numa request real quem seta é o controller;
    # sem isto o should_assign_conversation? seria false por acidente e o teste
    # passaria verde sem exercitar NADA.
    before { Current.account = account }

    after { Current.reset }

    it 'keeps the original owner when another agent reopens it (gate ON)' do
      enable_gate!
      Conversations::ToggleStatusService.new(conversation: resolved, params: { status: 'open' }, user: intruder).perform

      expect(resolved.reload.status).to eq('open')       # reabrir continua permitido
      expect(resolved.reload.assignee_id).to eq(owner.id) # mas NÃO troca de dono
    end

    it 'still hands the conversation over on reopen with the gate OFF (upstream behaviour)' do
      Conversations::ToggleStatusService.new(conversation: resolved, params: { status: 'open' }, user: intruder).perform

      expect(resolved.reload.assignee_id).to eq(intruder.id)
    end
  end

  describe '(b) bulk_actions_job' do
    it 'skips the assignment and creates NO request' do
      enable_gate!
      BulkActionsJob.perform_now(
        account_id: account.id, user_id: intruder.id,
        params: { type: 'Conversation', ids: [conversation.display_id], fields: { assignee_id: intruder.id } }
      )

      expect(conversation.reload.assignee_id).to eq(owner.id)
      # 500 conversas selecionadas não podem virar 500 pedidos (DoS social).
      expect(ConversationTakeoverRequest.count).to eq(0)
    end

    # O par do teste acima: sem isto, um bulk que no-op'a por engano (params
    # errados) faria o teste de cima passar verde sem exercitar o guard.
    it 'assigns normally with the gate OFF (proves the bulk really runs)' do
      BulkActionsJob.perform_now(
        account_id: account.id, user_id: intruder.id,
        params: { type: 'Conversation', ids: [conversation.display_id], fields: { assignee_id: intruder.id } }
      )

      expect(conversation.reload.assignee_id).to eq(intruder.id)
    end
  end
end

# A metade que importa mais: o guard não pode quebrar quem sempre pôde atribuir.
RSpec.describe 'D1 NÃO pode quebrar os caminhos legítimos' do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:owner) { create(:user, account: account, role: :agent) }
  let(:other) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: owner, status: :open) }

  before do
    account.update!(settings: account.settings.merge('takeover_request_gate' => true))
    create(:inbox_member, user: owner, inbox: inbox)
    create(:inbox_member, user: other, inbox: inbox)
  end

  # action_service.rb faz update!(assignee_id:) direto — passa por fora do
  # controller de propósito.
  it 'automation (ActionService) still changes the owner' do
    ActionService.new(conversation).assign_agent([other.id])
    expect(conversation.reload.assignee_id).to eq(other.id)
  end

  # ESTE é o teste que documenta por que o guard NÃO mora no modelo:
  # Macros::ExecutionService seta Current.user = user antes de rodar.
  it 'macros still change the owner (Current.user is set — a model guard would break this)' do
    macro = create(:macro, account: account, created_by: owner, updated_by: owner,
                           actions: [{ action_name: 'assign_agent', action_params: [other.id] }])
    Macros::ExecutionService.new(macro, conversation, owner).perform

    expect(conversation.reload.assignee_id).to eq(other.id)
  end

  it 'the assignment service itself stays free of the gate' do
    Conversations::AssignmentService.new(conversation: conversation, assignee_id: other.id).perform
    expect(conversation.reload.assignee_id).to eq(other.id)
  end
end
# rubocop:enable RSpec/MultipleDescribes, RSpec/DescribeClass
