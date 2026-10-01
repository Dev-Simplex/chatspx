require 'rails_helper'

RSpec.describe Captain::Behavior::SkipLabelsLock do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }

  def allows?(etiquetas)
    account.update!(custom_attributes: { 'captain_etiquetas_sem_ia' => etiquetas })
    described_class.new(account).allows?(conversation)
  end

  it 'allows everything when the account has no configuration' do
    conversation.update_labels(['portaria'])

    expect(described_class.new(account).allows?(conversation)).to be true
  end

  it 'allows everything when the list is blank' do
    conversation.update_labels(['portaria'])

    expect(allows?(['', nil])).to be true
  end

  it 'blocks a conversation with a configured label' do
    conversation.update_labels(['portaria'])

    expect(allows?(['portaria'])).to be false
  end

  it 'blocks a conversation whose contact has a configured label' do
    conversation.contact.update_labels(['portaria'])

    expect(allows?(['portaria'])).to be false
  end

  it 'ignores case and surrounding spaces in the configuration' do
    conversation.update_labels(['portaria'])

    expect(allows?([' Portaria '])).to be false
  end

  it 'allows a conversation whose labels are not configured' do
    conversation.update_labels(['vendas'])

    expect(allows?(['portaria'])).to be true
  end
end
