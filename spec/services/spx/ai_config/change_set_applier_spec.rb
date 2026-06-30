require 'rails_helper'

RSpec.describe Spx::AiConfig::ChangeSetApplier do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account, config: { 'instructions' => 'Original' }) }

  def cs(id, operations)
    { 'change_set_id' => id, 'account_id' => account.id, 'author' => 'almiral:test',
      'approved_by' => 'u_1', 'operations' => operations }
  end

  describe 'validate_operation! por tipo' do
    it 'exige assistant_id em ops assistant-scoped' do
      expect do
        described_class.new(cs('cs_a', [{ 'type' => 'update_instructions', 'instructions' => 'x' }]))
      end.to raise_error(described_class::InvalidChangeSet, /assistant_id ausente/)
    end

    it 'NAO exige assistant_id em set_credential (account-scoped)' do
      expect do
        described_class.new(cs('cs_b', [{ 'type' => 'set_credential', 'provider' => 'google',
                                          'settings' => { 'google_maps_key' => 'k' } }]))
      end.not_to raise_error
    end
  end

  describe '#apply! + revert! update_instructions' do
    it 'aplica, audita e reverte ao snapshot' do
      record = described_class.new(cs('cs_ui', [{ 'type' => 'update_instructions',
                                                  'assistant_id' => assistant.id, 'instructions' => 'Nova' }])).apply!
      expect(record).to be_applied
      expect(assistant.reload.config['instructions']).to eq('Nova')

      described_class.revert!('cs_ui')
      expect(assistant.reload.config['instructions']).to eq('Original')
      expect(record.reload).to be_reverted
    end

    it 'e idempotente: reaplicar o mesmo change_set_id e no-op' do
      applier = described_class.new(cs('cs_idem', [{ 'type' => 'update_instructions',
                                                     'assistant_id' => assistant.id, 'instructions' => 'A' }]))
      r1 = applier.apply!
      r2 = described_class.new(cs('cs_idem', [{ 'type' => 'update_instructions',
                                                'assistant_id' => assistant.id, 'instructions' => 'A' }])).apply!
      expect(r2.id).to eq(r1.id)
      expect(AiConfigChange.where(change_set_id: 'cs_idem').count).to eq(1)
    end
  end

  describe 'arm_tool / disarm_tool' do
    it 'arma uma tool valida e reverte a lista inteira' do
      described_class.new(cs('cs_arm', [{ 'type' => 'arm_tool', 'assistant_id' => assistant.id,
                                          'tool_id' => 'add_contact_note' }])).apply!
      expect(assistant.reload.config['tools']).to include('add_contact_note')

      described_class.revert!('cs_arm')
      expect(Array(assistant.reload.config['tools'])).not_to include('add_contact_note')
    end

    it 'recusa tool nao disponivel' do
      expect do
        described_class.new(cs('cs_badtool', [{ 'type' => 'arm_tool', 'assistant_id' => assistant.id,
                                                'tool_id' => 'tool_inexistente' }])).apply!
      end.to raise_error(described_class::InvalidChangeSet, /nao disponivel/)
    end
  end

  describe 'set_credential' do
    it 'cria a integracao e mascara segredos no diff' do
      op = { 'type' => 'set_credential', 'provider' => 'vista',
             'settings' => { 'vista_api_key' => 'SUPERSECRETKEY123', 'vista_base_url' => 'https://x' } }
      diff = described_class.new(cs('cs_cred', [op])).dry_run.first
      expect(diff[:after]['vista_api_key']).not_to eq('SUPERSECRETKEY123')
      expect(diff[:after]['vista_base_url']).to eq('https://x')

      described_class.new(cs('cs_cred', [op])).apply!
      integ = account.account_integrations.find_by(provider: 'vista')
      expect(integ.settings['vista_api_key']).to eq('SUPERSECRETKEY123')

      described_class.revert!('cs_cred')
      expect(account.account_integrations.find_by(provider: 'vista')).to be_nil
    end
  end

  describe 'upsert_custom_tool' do
    def tool_op(tool)
      { 'type' => 'upsert_custom_tool', 'tool' => tool }
    end

    it 'cria uma custom tool nova (account-scoped) e reverte destruindo' do
      op = tool_op('title' => 'Consulta CEP', 'description' => 'Busca CEP',
                   'endpoint_url' => 'https://viacep.com.br/ws/01001000/json/',
                   'http_method' => 'GET', 'param_schema' => [])
      record = described_class.new(cs('cs_ct_new', [op])).apply!
      expect(record).to be_applied
      tool = account.captain_custom_tools.find_by(title: 'Consulta CEP')
      expect(tool).to be_present
      expect(tool.endpoint_url).to eq('https://viacep.com.br/ws/01001000/json/')

      described_class.revert!('cs_ct_new')
      expect(account.captain_custom_tools.find_by(title: 'Consulta CEP')).to be_nil
      expect(record.reload).to be_reverted
    end

    it 'edita uma custom tool existente (por slug) e reverte restaurando o snapshot' do
      existing = create(:captain_custom_tool, account: account, title: 'Tool X',
                                              description: 'old desc', endpoint_url: 'https://api.example.com/x')
      op = tool_op('slug' => existing.slug, 'description' => 'novo desc',
                   'endpoint_url' => 'https://api.example.com/y')
      described_class.new(cs('cs_ct_edit', [op])).apply!
      existing.reload
      expect(existing.description).to eq('novo desc')
      expect(existing.endpoint_url).to eq('https://api.example.com/y')

      described_class.revert!('cs_ct_edit')
      existing.reload
      expect(existing.description).to eq('old desc')
      expect(existing.endpoint_url).to eq('https://api.example.com/x')
    end

    it 'mascara segredos de auth no diff (nao vaza token)' do
      op = tool_op('title' => 'Auth Tool', 'endpoint_url' => 'https://api.example.com/z',
                   'auth_type' => 'bearer', 'auth_config' => { 'token' => 'SUPERSECRET' })
      diff = described_class.new(cs('cs_ct_auth', [op])).dry_run.first
      expect(diff[:after]['auth_config']['token']).to eq('***')
      expect(diff.to_s).not_to include('SUPERSECRET')
    end

    it 'e idempotente: reaplicar o mesmo change_set_id nao duplica a tool' do
      op = tool_op('title' => 'Idem Tool', 'endpoint_url' => 'https://api.example.com/i')
      r1 = described_class.new(cs('cs_ct_idem', [op])).apply!
      r2 = described_class.new(cs('cs_ct_idem', [op])).apply!
      expect(r2.id).to eq(r1.id)
      expect(account.captain_custom_tools.where(title: 'Idem Tool').count).to eq(1)
    end

    it 'NAO exige assistant_id (account-scoped)' do
      expect do
        described_class.new(cs('cs_ct_scope', [tool_op('title' => 'T',
                                                       'endpoint_url' => 'https://api.example.com/t')]))
      end.not_to raise_error
    end
  end

  describe 'update_behavior' do
    it 'faz merge e reverte o hash inteiro' do
      described_class.new(cs('cs_beh', [{ 'type' => 'update_behavior', 'assistant_id' => assistant.id,
                                          'behavior' => { 'debounce_seconds' => 8 } }])).apply!
      expect(assistant.reload.behavior['debounce_seconds']).to eq(8)

      described_class.revert!('cs_beh')
      expect(assistant.reload.behavior['debounce_seconds']).to be_nil
    end

    it 'recusa chave de behavior fora da whitelist' do
      expect do
        described_class.new(cs('cs_badbeh', [{ 'type' => 'update_behavior', 'assistant_id' => assistant.id,
                                               'behavior' => { 'hack' => 1 } }])).apply!
      end.to raise_error(described_class::InvalidChangeSet, /invalidas/)
    end
  end

  describe 'set_eligibility' do
    let(:inbox) { create(:inbox, account: account) }

    it 'reconcilia as inboxes elegiveis e reverte' do
      described_class.new(cs('cs_elig', [{ 'type' => 'set_eligibility', 'assistant_id' => assistant.id,
                                           'inbox_ids' => [inbox.id] }])).apply!
      expect(assistant.reload.captain_inboxes.pluck(:inbox_id)).to eq([inbox.id])

      described_class.revert!('cs_elig')
      expect(assistant.reload.captain_inboxes.pluck(:inbox_id)).to eq([])
    end

    it 'bloqueia inbox de outra conta (TenantViolation)' do
      other = create(:inbox, account: create(:account))
      expect do
        described_class.new(cs('cs_tenant', [{ 'type' => 'set_eligibility', 'assistant_id' => assistant.id,
                                               'inbox_ids' => [other.id] }])).apply!
      end.to raise_error(described_class::TenantViolation)
    end
  end

  describe 'tenant isolation' do
    it 'recusa assistant de outra conta' do
      other = create(:captain_assistant, account: create(:account))
      expect do
        described_class.new(cs('cs_x', [{ 'type' => 'update_instructions',
                                          'assistant_id' => other.id, 'instructions' => 'x' }])).apply!
      end.to raise_error(described_class::TenantViolation)
    end
  end

  describe 'status:failed em txn separada' do
    it 'grava AiConfigChange failed com error_message e re-raise' do
      op = { 'type' => 'arm_tool', 'assistant_id' => assistant.id, 'tool_id' => 'tool_inexistente' }
      expect { described_class.new(cs('cs_fail', [op])).apply! }.to raise_error(described_class::InvalidChangeSet)

      rec = AiConfigChange.find_by(change_set_id: 'cs_fail')
      expect(rec).to be_present
      expect(rec).to be_failed
      expect(rec.error_message).to match(/nao disponivel/)
    end
  end
end
