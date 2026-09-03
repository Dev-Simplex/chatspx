require 'rails_helper'

RSpec.describe AutomationRules::ActionService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:rule) { create(:automation_rule, account: account) }

  it 'assina o disparo quando a conta registrou a URL' do
    webhook = create(:webhook, account: account, url: 'https://automacao.exemplo.com/h',
                               subscriptions: ['conversation_created'])
    capturado = nil
    allow(WebhookJob).to receive(:perform_later) { |*args| capturado = args }

    described_class.new(rule, account, conversation).send(:send_webhook_event, ['https://automacao.exemplo.com/h'])

    expect(capturado[3][:secret]).to eq(webhook.secret)
    expect(capturado[3][:secret]).to be_present
  end

  it 'segue disparando sem assinatura quando nao ha URL registrada' do
    capturado = nil
    allow(WebhookJob).to receive(:perform_later) { |*args| capturado = args }

    described_class.new(rule, account, conversation).send(:send_webhook_event, ['https://nao-registrada.exemplo.com/h'])

    expect(capturado[3][:secret]).to be_nil
  end
end
