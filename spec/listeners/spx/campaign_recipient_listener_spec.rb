# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spx::CampaignRecipientListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              sync_templates: false, validate_provider_config: false).inbox
  end
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:campaign) { create(:campaign, account: account, inbox: inbox, template_name: 'aniversario') }
  let(:template) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     created_at: 1.hour.ago)
  end
  let!(:recipient) do
    CampaignRecipient.create!(campaign: campaign, account: account, contact: contact, conversation: conversation,
                              phone_number: '+5566999990000', status: :sent, sent_at: 1.hour.ago, message_id: template.id)
  end

  def event(name, message)
    Events::Base.new(name, Time.zone.now, message: message)
  end

  it 'leva o status da mensagem do template ao destinatário' do
    template.update!(status: :delivered)

    listener.message_updated(event('message.updated', template))

    expect(recipient.reload).to be_delivered
  end

  it 'marca respondido na mensagem recebida depois do envio' do
    resposta = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                                sender: contact)

    listener.message_created(event('message.created', resposta))

    expect(recipient.reload).to be_replied
  end
end
