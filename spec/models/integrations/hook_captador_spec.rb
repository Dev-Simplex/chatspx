require 'rails_helper'

RSpec.describe Integrations::Hook do
  include CaptadorSigningHelpers

  let(:account) { create(:account) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:hook) { captador_hook_for(account) }

  it 'normalizes whitespace, leading zeros and duplicate inbox IDs' do
    hook.update!(settings: hook.settings.merge('allowed_inbox_ids' => " 0#{inbox.id}, #{inbox.id} "))
    expect(hook.reload.settings['allowed_inbox_ids']).to eq(inbox.id.to_s)
    hook.update!(settings: hook.settings.merge('allowed_inbox_ids' => '   '))
    expect(hook.reload.settings['allowed_inbox_ids']).to eq('')
  end

  it 'rejects malformed, missing, unsupported and foreign inboxes without changing the stored configuration' do
    foreign = create(:channel_api).inbox
    unsupported = create(:inbox, account: account)
    ['1x', '1,,2', '0', '-1', '1.0', [inbox.id], foreign.id.to_s, unsupported.id.to_s, '999999999'].each do |value|
      expect(hook.update(settings: hook.settings.merge('allowed_inbox_ids' => value))).to be(false)
      expect(hook.reload.settings['allowed_inbox_ids']).to be_nil
    end
  end

  it 'preserves blank secrets and rejects short rotations before encryption' do
    ['', '   ', nil].each do |value|
      hook.update!(settings: hook.settings.merge('shared_secret' => value))
      expect(hook.reload.captador_shared_secret).to eq('s' * 40)
    end
    expect(hook.update(settings: hook.settings.merge('shared_secret' => 'short'))).to be(false)
    expect(hook.save).to be(false)
    expect(hook.reload.captador_shared_secret).to eq('s' * 40)
    hook.update!(settings: hook.settings.merge('shared_secret' => 'r' * 40))
    expect(hook.reload.captador_shared_secret).to eq('r' * 40)
  end

  it 'recomputes effective inboxes after removal without including another account' do
    hook.update!(settings: hook.settings.merge('allowed_inbox_ids' => inbox.id.to_s))
    expect(hook.captador_inbox_state[:effective_inboxes].pluck(:id)).to eq([inbox.id])
    id = inbox.id
    inbox.destroy!
    create(:channel_api)
    expect(hook.captador_inbox_state).to eq(effective_inboxes: [], unavailable_inbox_ids: [id])
  end
end
