require 'rails_helper'

RSpec.describe Flow do
  let(:account) { create(:account) }

  def build_flow(nodes:, edges: [])
    build(:flow, account: account, definition: { 'nodes' => nodes, 'edges' => edges })
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:created_by).class_name('User').optional }
    it { is_expected.to belong_to(:updated_by).class_name('User').optional }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:trigger_type).with_values(manual: 0, conversation_event: 1, schedule: 2, keyword: 3, external_webhook: 4) }
    it { is_expected.to define_enum_for(:visibility).with_values(personal: 0, global: 1) }
    it { is_expected.to define_enum_for(:reentry_policy).with_values(once: 0, re_enroll: 1, re_enroll_after: 2) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }

    it 'is valid with an empty nodes/edges definition' do
      expect(build_flow(nodes: [])).to be_valid
    end

    it 'is valid with a supported action node' do
      node = { 'id' => 'n1', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => ['vip'] }
      expect(build_flow(nodes: [node])).to be_valid
    end

    it 'rejects a definition that is not a hash with nodes[]/edges[]' do
      flow = build(:flow, account: account, definition: { 'foo' => 'bar' })
      expect(flow).not_to be_valid
      expect(flow.errors[:definition].join).to include('nodes[] and edges[]')
    end

    it 'rejects nodes whose elements are not objects (would break the walker)' do
      flow = build(:flow, account: account, definition: { 'nodes' => ['not-a-hash'], 'edges' => [] })
      expect(flow).not_to be_valid
      expect(flow.errors[:definition].join).to include('nodes must be objects')
    end

    it 'rejects edges whose elements are not objects' do
      flow = build(:flow, account: account, definition: { 'nodes' => [], 'edges' => [42] })
      expect(flow).not_to be_valid
      expect(flow.errors[:definition].join).to include('edges must be objects')
    end

    it 'rejects an action node with an unsupported action_name' do
      node = { 'id' => 'n1', 'type' => 'action', 'action_name' => 'do_evil' }
      flow = build_flow(nodes: [node])
      expect(flow).not_to be_valid
      expect(flow.errors[:definition].join).to include('unsupported actions').and(include('do_evil'))
    end

    it 'accepts the F1 nodes send_template and set_attribute' do
      nodes = [
        { 'id' => 'n1', 'type' => 'action', 'action_name' => 'send_template' },
        { 'id' => 'n2', 'type' => 'action', 'action_name' => 'set_attribute' }
      ]
      expect(build_flow(nodes: nodes)).to be_valid
    end

    it 'does not flag non-action nodes (trigger/condition/wait) as unsupported actions' do
      nodes = [
        { 'id' => 't1', 'type' => 'trigger' },
        { 'id' => 'c1', 'type' => 'condition', 'conditions' => [] },
        { 'id' => 'w1', 'type' => 'wait', 'params' => { 'for_minutes' => 60 } }
      ]
      expect(build_flow(nodes: nodes)).to be_valid
    end

    # Meta recusa uma interativa sem corpo ("interactive.body.text is required"): a mensagem morre
    # com status failed, o contato nao ve nada e o wait_for_reply seguinte arma a espera do mesmo
    # jeito — atendente ve "menu enviado", cliente ve silencio. Barrado na gravacao.
    describe 'send_interactive sendability' do
      def interactive_node(content, items)
        { 'id' => 'n1', 'type' => 'action', 'action_name' => 'send_interactive',
          'action_params' => [{ 'content' => content, 'items' => items }] }
      end

      let(:items) { [{ 'title' => 'Boleto', 'value' => 'boleto' }] }

      it 'accepts a node with body and one titled option' do
        expect(build_flow(nodes: [interactive_node('Escolha uma opcao:', items)])).to be_valid
      end

      it 'rejects a blank body' do
        flow = build_flow(nodes: [interactive_node('   ', items)])
        expect(flow).not_to be_valid
        expect(flow.errors[:definition].join).to include('node n1').and(include('non-blank content'))
      end

      it 'rejects a missing body' do
        node = { 'id' => 'n1', 'type' => 'action', 'action_name' => 'send_interactive',
                 'action_params' => [{ 'items' => items }] }
        expect(build_flow(nodes: [node])).not_to be_valid
      end

      it 'rejects a node without any titled option' do
        flow = build_flow(nodes: [interactive_node('Escolha:', [{ 'title' => '  ', 'value' => 'x' }])])
        expect(flow).not_to be_valid
        expect(flow.errors[:definition].join).to include('at least one option with a title')
      end

      it 'rejects a node with no action_params at all' do
        node = { 'id' => 'n1', 'type' => 'action', 'action_name' => 'send_interactive' }
        expect(build_flow(nodes: [node])).not_to be_valid
      end

      it 'ignores other action nodes' do
        node = { 'id' => 'n1', 'type' => 'action', 'action_name' => 'send_message', 'action_params' => [''] }
        expect(build_flow(nodes: [node])).to be_valid
      end
    end
  end

  describe '.active scope' do
    it 'returns only active flows' do
      active = create(:flow, account: account, active: true)
      create(:flow, account: account, active: false)
      expect(described_class.active).to eq([active])
    end
  end

  # O #index listava TODOS os flows da conta, enquanto a FlowPolicy#show? ja exigia global? ||
  # author? — o flow pessoal alheio saia inteiro (trigger_config + definition) na listagem.
  describe '.with_visibility' do
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:other_agent) { create(:user, account: account, role: :agent) }

    it 'returns the global flows plus the personal ones of this user' do
      shared = create(:flow, account: account, visibility: :global)
      mine = create(:flow, account: account, visibility: :personal, created_by: agent)
      theirs = create(:flow, account: account, visibility: :personal, created_by: other_agent)

      visible = account.flows.with_visibility(agent)
      expect(visible).to include(shared, mine)
      expect(visible).not_to include(theirs)
    end

    it 'keeps the account scope it was chained on' do
      other_account_flow = create(:flow, account: create(:account), visibility: :global)
      create(:flow, account: account, visibility: :global)

      expect(account.flows.with_visibility(agent)).not_to include(other_account_flow)
    end

    it 'falls back to the global flows when there is no user' do
      create(:flow, account: account, visibility: :personal, created_by: agent)
      shared = create(:flow, account: account, visibility: :global)

      expect(account.flows.with_visibility(nil)).to eq([shared])
    end
  end

  describe '#nodes / #edges' do
    it 'reads nodes and edges from the definition' do
      node = { 'id' => 'n1', 'type' => 'action', 'action_name' => 'add_label' }
      flow = build_flow(nodes: [node], edges: [{ 'from' => 'n1', 'to' => nil }])
      expect(flow.nodes.first['id']).to eq('n1')
      expect(flow.edges.first['from']).to eq('n1')
    end
  end

  describe 'external_webhook token (R-2)' do
    def webhook_flow(config = {})
      create(:flow, account: account, trigger_type: :external_webhook, trigger_config: config)
    end

    it 'generates a strong token on save when the flow is a webhook' do
      flow = webhook_flow
      expect(flow.webhook_token).to match(/\A[0-9a-f]{48}\z/) # SecureRandom.hex(24) = 192 bits
    end

    it 'does not generate a token for non-webhook flows' do
      expect(create(:flow, account: account).webhook_token).to be_nil
    end

    it 'keeps the token stable across edits (URL never changes)' do
      flow = webhook_flow
      original = flow.webhook_token
      flow.update!(name: 'renamed', trigger_config: {})
      expect(flow.reload.webhook_token).to eq(original)
    end

    it 'is backend-authoritative: ignores a client-supplied token on create' do
      flow = webhook_flow('webhook_token' => 'client-chosen-weak-token')
      expect(flow.webhook_token).not_to eq('client-chosen-weak-token')
      expect(flow.webhook_token).to match(/\A[0-9a-f]{48}\z/)
    end

    it 'is backend-authoritative: a client cannot rotate the token on update' do
      flow = webhook_flow
      original = flow.webhook_token
      flow.update!(trigger_config: { 'webhook_token' => 'attacker-rotated' })
      expect(flow.reload.webhook_token).to eq(original)
    end

    it 'strips a client-supplied token from a flow that is NOT a webhook' do
      flow = create(:flow, account: account, trigger_type: :manual,
                           trigger_config: { 'webhook_token' => '1', 'foo' => 'bar' })
      expect(flow.reload.trigger_config).to eq('foo' => 'bar')
    end

    # O caminho de DUAS requisicoes: com o antigo `return unless external_webhook?` o "1" entrava
    # cru no jsonb da criacao `manual` e, ao virar webhook, ja era o valor PERSISTIDO — ou seja, o
    # cliente escolhia a credencial do endpoint publico.
    it 'does not let the client fix the token in two steps (manual then external_webhook)' do
      flow = create(:flow, account: account, trigger_type: :manual, trigger_config: { 'webhook_token' => '1' })
      expect(flow.reload.webhook_token).to be_nil

      flow.update!(trigger_type: :external_webhook, trigger_config: { 'webhook_token' => '1' })
      expect(flow.reload.webhook_token).not_to eq('1')
      expect(flow.webhook_token).to match(/\A[0-9a-f]{48}\z/)
    end

    # Dado sujo GRAVADO antes do descarte (a primeira das duas requisicoes ja feita em producao):
    # o token do cliente nao pode ser herdado so por estar persistido.
    it 'does not inherit a legacy client-injected token when the flow becomes a webhook' do
      flow = create(:flow, account: account, trigger_type: :manual)
      flow.update_column(:trigger_config, { 'webhook_token' => '1' }) # rubocop:disable Rails/SkipsModelValidations

      flow.reload.update!(trigger_type: :external_webhook)
      expect(flow.reload.webhook_token).not_to eq('1')
      expect(flow.webhook_token).to match(/\A[0-9a-f]{48}\z/)
    end

    describe '.for_webhook_token' do
      it 'finds an active webhook flow by its token' do
        flow = webhook_flow
        expect(described_class.for_webhook_token(flow.webhook_token)).to eq(flow)
      end

      it 'returns nil for a blank token' do
        expect(described_class.for_webhook_token('')).to be_nil
        expect(described_class.for_webhook_token(nil)).to be_nil
      end

      it 'does not match a flow of another trigger type' do
        flow = webhook_flow
        token = flow.webhook_token
        flow.update!(trigger_type: :manual)

        expect(flow.reload.webhook_token).to eq(token) # preservado: a mesma URL volta se reativar
        expect(described_class.for_webhook_token(token)).to be_nil
      end
    end
  end

  # O partial serializa o trigger_config inteiro para todo mundo da conta que enxerga o flow; o
  # webhook_token dentro dele e a credencial do endpoint publico.
  describe '#trigger_config_for' do
    let(:author) { create(:user, account: account, role: :agent) }
    let(:flow) { create(:flow, account: account, trigger_type: :external_webhook, created_by: author) }

    def account_user_for(user)
      account.account_users.find_by(user_id: user.id)
    end

    it 'gives the whole config to the author' do
      expect(flow.trigger_config_for(author, account_user_for(author))['webhook_token']).to eq(flow.webhook_token)
    end

    it 'gives the whole config to an administrator' do
      admin = create(:user, account: account, role: :administrator)
      expect(flow.trigger_config_for(admin, account_user_for(admin))['webhook_token']).to eq(flow.webhook_token)
    end

    it 'omits the token for another agent' do
      other = create(:user, account: account, role: :agent)
      expect(flow.trigger_config_for(other, account_user_for(other))).not_to have_key('webhook_token')
    end

    it 'omits the token when there is no identified user' do
      expect(flow.trigger_config_for(nil, nil)).not_to have_key('webhook_token')
    end

    it 'leaves a config without a token untouched' do
      plain = create(:flow, account: account, trigger_config: { 'event_name' => 'conversation_created' })
      expect(plain.trigger_config_for(nil, nil)).to eq('event_name' => 'conversation_created')
    end
  end

  describe 'attachments' do
    it 'supports file attachments (preserves @macro/@rule.files for send_attachment)' do
      flow = create(:flow, account: account)
      flow.files.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
      expect(flow.files).to be_attached
    end

    it 'exposes file_base_data for serialization' do
      flow = create(:flow, account: account)
      flow.files.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
      data = flow.file_base_data.first
      expect(data[:flow_id]).to eq(flow.id)
      expect(data[:filename]).to eq('avatar.png')
    end
  end
end
