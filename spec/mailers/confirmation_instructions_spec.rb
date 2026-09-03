# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Devise::Mailer' do
  describe 'notify' do
    let(:account) { create(:account) }
    let!(:confirmable_user) { create(:user, inviter: inviter_val, account: account) }
    let(:inviter_val) { nil }
    let(:mail) { Devise::Mailer.confirmation_instructions(confirmable_user.reload, nil, {}) }

    before do
      # to verify the token in email
      confirmable_user.update!(confirmed_at: nil)
      confirmable_user.send(:generate_confirmation_token)
    end

    it 'has the correct header data' do
      # `Devise.mailer_sender` e lido no BOOT a partir de MAILER_SENDER_EMAIL
      # (config/initializers/devise.rb:15), entao `with_modified_env` nao alcanca. O spec
      # cravava 'accounts@chatwoot.com', que e o valor de FALLBACK: so passava em maquina
      # SEM a variavel. Lendo a mesma fonte que o codigo le, passa em qualquer lugar.
      # Mesmo idioma de app/presenters/mail_presenter.rb:178.
      expected_reply_to = Mail::Address.new(ENV.fetch('MAILER_SENDER_EMAIL', 'SPX - CHAT <accounts@chatwoot.com>')).address
      expect(mail.reply_to).to contain_exactly(expected_reply_to)
      expect(mail.to).to contain_exactly(confirmable_user.email)
      # `Devise.parent_mailer = ApplicationMailer`, e este envio nao carrega conta, entao
      # `switch_locale` cai em `I18n.default_locale` — pt_BR por decisao nossa. O assunto vem
      # do proprio i18n do Devise; cravar o ingles testava o locale, nao o mailer.
      expect(mail.subject).to eq(
        I18n.t('devise.mailer.confirmation_instructions.subject', locale: I18n.default_locale)
      )
    end

    it 'uses the user\'s name' do
      expect(mail.body).to match("Hi #{CGI.escapeHTML(confirmable_user.name)},")
    end

    it 'does not refer to the inviter and their account' do
      expect(mail.body).not_to match('has invited you to try out Chatwoot!')
      expect(mail.body).to match('We have a suite of powerful tools ready for you to explore.')
    end

    it 'sends a confirmation link' do
      expect(mail.body).to include("app/auth/confirmation?confirmation_token=#{confirmable_user.confirmation_token}")
      expect(mail.body).not_to include('app/auth/password/edit')
    end

    context 'when there is an inviter' do
      let(:inviter_val) { create(:user, :administrator, skip_confirmation: true, account: account) }

      it 'refers to the inviter and their account' do
        expect(mail.body).to match(
          "#{CGI.escapeHTML(inviter_val.name)}, with #{CGI.escapeHTML(account.name)}, has invited you to try out Chatwoot."
        )
        expect(mail.body).not_to match('We have a suite of powerful tools ready for you to explore.')
      end

      it 'sends a password reset link' do
        expect(mail.body).to include('app/auth/password/edit?reset_password_token')
        expect(mail.body).not_to include('app/auth/confirmation')
      end
    end

    context 'when user updates the email' do
      before do
        confirmable_user.update!(email: 'user@example.com')
      end

      it 'sends a confirmation link' do
        confirmation_mail = Devise::Mailer.confirmation_instructions(confirmable_user.reload, nil, {})

        expect(confirmation_mail.body).to include('app/auth/confirmation?confirmation_token')
        expect(confirmation_mail.body).not_to include('app/auth/password/edit')
        expect(confirmable_user.unconfirmed_email.blank?).to be false
      end
    end

    context 'when user is confirmed and updates the email' do
      before do
        confirmable_user.confirm
        confirmable_user.update!(email: 'user@example.com')
      end

      it 'sends a confirmation link' do
        confirmation_mail = Devise::Mailer.confirmation_instructions(confirmable_user.reload, nil, {})

        expect(confirmation_mail.body).to include('app/auth/confirmation?confirmation_token')
        expect(confirmation_mail.body).not_to include('app/auth/password/edit')
        expect(confirmable_user.unconfirmed_email.blank?).to be false
      end
    end

    context 'when user already confirmed' do
      before do
        confirmable_user.confirm
        confirmable_user.account_users.last.destroy!
      end

      it 'send instructions with the link to login' do
        confirmation_mail = Devise::Mailer.confirmation_instructions(confirmable_user.reload, nil, {})
        expect(confirmation_mail.body).to include('/auth/sign_in')
      end
    end
  end
end
