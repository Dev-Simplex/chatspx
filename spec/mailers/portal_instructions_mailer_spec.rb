# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PortalInstructionsMailer do
  describe 'send_cname_instructions' do
    let!(:account) { create(:account) }
    let!(:portal) { create(:portal, account: account, custom_domain: 'help.example.com') }
    let(:recipient_email) { 'admin@example.com' }
    let(:class_instance) { described_class.new }

    before do
      allow(described_class).to receive(:new).and_return(class_instance)
      allow(class_instance).to receive(:smtp_config_set_or_development?).and_return(true)
    end

    context 'when target domain is available' do
      it 'sends email with cname instructions' do
        with_modified_env HELPCENTER_URL: 'https://help.chatwoot.com' do
          mail = described_class.send_cname_instructions(portal: portal, recipient_email: recipient_email).deliver_now

          expect(mail.to).to eq([recipient_email])
          # O assunto vem de `portals.send_instructions.subject`. Este mailer nao tem conta,
          # entao `ApplicationMailer#switch_locale` cai em `I18n.default_locale` — que e pt_BR
          # por decisao nossa (config/application.rb:47). Cravar o ingles testava o locale.
          expect(mail.subject).to eq(
            I18n.t('portals.send_instructions.subject', custom_domain: portal.custom_domain, locale: I18n.default_locale)
          )
          expect(mail.body.encoded).to include('help.example.com CNAME help.chatwoot.com')
        end
      end
    end

    context 'when helpcenter url is not available but frontend url is' do
      it 'uses frontend url as target domain' do
        with_modified_env HELPCENTER_URL: '', FRONTEND_URL: 'https://app.chatwoot.com' do
          mail = described_class.send_cname_instructions(portal: portal, recipient_email: recipient_email).deliver_now

          expect(mail.to).to eq([recipient_email])
          expect(mail.body.encoded).to include('help.example.com CNAME app.chatwoot.com')
        end
      end
    end

    context 'when no target domain is available' do
      it 'does not send email' do
        with_modified_env HELPCENTER_URL: '', FRONTEND_URL: '' do
          mail = described_class.send_cname_instructions(portal: portal, recipient_email: recipient_email).deliver_now

          expect(mail).to be_nil
        end
      end
    end
  end
end
