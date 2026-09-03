require 'rails_helper'
describe InstallationWebhookListener do
  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let!(:event) { Events::Base.new(event_name, Time.zone.now, account: account) }

  describe '#account_created' do
    let(:event_name) { :'account.created' }

    context 'when installation config is not configured' do
      it 'does not trigger webhook' do
        expect(WebhookJob).to receive(:perform_later).exactly(0).times
        listener.account_created(event)
      end
    end

    context 'when installation config is configured' do
      # Bloco 4.13: este evento saia sem assinatura. Sem o segredo de instalacao
      # configurado ele segue sem assinar, que e o comportamento de hoje — mas o tipo e o
      # argumento passam a ser explicitos.
      it 'triggers webhook' do
        create(:installation_config, name: 'INSTALLATION_EVENTS_WEBHOOK_URL', value: 'https://test.com')
        expect(WebhookJob).to receive(:perform_later).with(
          'https://test.com', account.webhook_data.merge(event: 'account_created', users: []),
          :account_webhook, secret: nil
        ).once
        listener.account_created(event)
      end

      it 'assina quando o segredo de instalacao esta configurado' do
        create(:installation_config, name: 'INSTALLATION_EVENTS_WEBHOOK_URL', value: 'https://test.com')
        create(:installation_config, name: 'INSTALLATION_EVENTS_WEBHOOK_SECRET', value: 'segredo-da-instalacao')

        expect(WebhookJob).to receive(:perform_later).with(
          'https://test.com', anything, :account_webhook, secret: 'segredo-da-instalacao'
        ).once
        listener.account_created(event)
      end
    end
  end
end
