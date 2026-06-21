require 'rails_helper'

RSpec.describe Attachments::GalleryScopeBuilder, type: :service do
  subject(:builder) { described_class.new(user: agent, account: account, filters: { type: 'image' }) }

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:foreign_inbox) { create(:inbox, account: account) }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  def create_attachment(target_inbox, file_type: :image, asset: 'sample.png', content_type: 'image/png')
    conversation = create(:conversation, account: account, inbox: target_inbox)
    message = create(:message, account: account, conversation: conversation, inbox: target_inbox)
    attachment = message.attachments.new(account_id: account.id, file_type: file_type)
    attachment.file.attach(io: Rails.root.join("spec/assets/#{asset}").open, filename: asset, content_type: content_type)
    attachment.save!
    attachment
  end

  it 'includes attachments from inboxes the agent is assigned to' do
    visible = create_attachment(inbox)
    expect(builder.deduped_scope.pluck(:id)).to include(visible.id)
  end

  it 'excludes attachments from inboxes the agent is not assigned to' do
    foreign = create_attachment(foreign_inbox)
    expect(builder.deduped_scope.pluck(:id)).not_to include(foreign.id)
  end

  it 'does not depend on Current (usable inside a job)' do
    create_attachment(inbox)
    Current.reset
    expect { builder.deduped_scope.to_a }.not_to raise_error
  end

  it 'returns an empty scope when the requester user is nil (deprovisioned)' do
    create_attachment(inbox)
    nil_user_builder = described_class.new(user: nil, account: account, filters: { type: 'image' })
    expect(nil_user_builder.deduped_scope.to_a).to be_empty
  end

  # §T5: uma data malformada não pode zerar a galeria silenciosamente.
  it 'ignores a malformed date filter instead of emptying the scope' do
    visible = create_attachment(inbox)
    garbage_builder = described_class.new(
      user: agent, account: account, filters: { type: 'image', after: 'lixo', before: 'também-lixo' }
    )
    expect(garbage_builder.deduped_scope.pluck(:id)).to include(visible.id)
  end

  it 'still applies a valid date filter' do
    old = travel_to(10.days.ago) { create_attachment(inbox) }
    recent = create_attachment(inbox)
    builder_with_date = described_class.new(
      user: agent, account: account, filters: { type: 'image', after: 2.days.ago.iso8601 }
    )
    ids = builder_with_date.deduped_scope.pluck(:id)
    expect(ids).to include(recent.id)
    expect(ids).not_to include(old.id)
  end
end
