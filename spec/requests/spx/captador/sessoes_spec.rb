require 'rails_helper'

# Login do Captador pela conta do ChatSPX (22 §2.3): identidade e papel, nenhum token criado.
RSpec.describe 'Spx::Captador::Sessoes', type: :request do
  include CaptadorSigningHelpers

  let(:path) { '/spx/captador/v1/sessoes' }
  let(:account) { create(:account) }
  let!(:hook) { captador_hook_for(account, allow_login: true) }
  let!(:user) { create(:user, account: account, role: :administrator) }

  def login(body = { email: user.email, password: 'Password1!' }, **)
    captador_post(path, body, hook: hook, **)
  end

  describe 'assinatura' do
    it 'recusa segredo errado com 401 sem corpo' do
      login(secret: 'outro-segredo')

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to be_empty
    end

    it 'recusa pedido fora da janela de 5 minutos' do
      login(timestamp: 6.minutes.ago.to_i)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'recusa conta sem o interruptor captador_integration' do
      account.update!(captador_integration: false)
      login

      expect(response).to have_http_status(:unauthorized)
    end

    it 'recusa hook desligado' do
      hook.update!(status: 'disabled')
      login

      expect(response).to have_http_status(:unauthorized)
    end

    it 'recusa a repetição exata de uma mutação assinada' do
      body = { email: user.email, password: 'Password1!' }
      timestamp = Time.now.to_i

      login(body, timestamp: timestamp)
      expect(response).to have_http_status(:ok)
      login(body, timestamp: timestamp)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'e-mail e senha' do
    it 'devolve identidade, papel e times sem criar token nem sessão' do
      team = create(:team, account: account, name: 'Comercial')
      create(:team_member, team: team, user: user)

      expect { login({ email: "  #{user.email.upcase} ", password: 'Password1!' }) }.not_to(change { user.reload.tokens })

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['user']).to include('id' => user.id, 'email' => user.email, 'name' => user.name)
      expect(body['account']).to eq('id' => account.id, 'name' => account.name, 'role' => 'administrator', 'permissions' => ['administrator'])
      expect(body['teams']).to eq([{ 'id' => team.id, 'name' => team.name }])
      expect(response.body).not_to include('access_token', 'pubsub_token')
      expect(response.headers['access-token']).to be_nil
    end

    it 'devolve o papel de agente' do
      agent = create(:user, account: account, role: :agent)
      login({ email: agent.email, password: 'Password1!' })

      expect(response.parsed_body['account']).to include('role' => 'agent', 'permissions' => ['agent'])
    end

    it 'responde 401 genérico para senha errada e para e-mail inexistente' do
      login({ email: user.email, password: 'errada' })
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq('error_code' => 'invalid_credentials')

      login({ email: 'ninguem@exemplo.com', password: 'Password1!' })
      expect(response.parsed_body).to eq('error_code' => 'invalid_credentials')
    end

    it 'recusa usuário que não pode entrar (não confirmado)' do
      user.update_column(:confirmed_at, nil) # rubocop:disable Rails/SkipsModelValidations
      login

      expect(response).to have_http_status(:unauthorized)
    end

    it 'manda usuário SAML para o SSO' do
      user.update!(provider: 'saml')
      login

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error_code']).to eq('saml_required')
    end

    it 'recusa quem não é membro da conta do hook' do
      outsider = create(:user, account: create(:account))
      login({ email: outsider.email, password: 'Password1!' })

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error_code']).to eq('invalid_credentials')
    end

    it 'só funciona no hook marcado com allow_login' do
      hook.update!(settings: hook.settings.merge('allow_login' => false))
      login

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error_code']).to eq('login_not_allowed')
    end
  end

  describe '2FA' do
    before { user.update!(otp_required_for_login: true) }

    it 'pede o código com 206 e mfa_token, sem identidade' do
      login

      expect(response).to have_http_status(:partial_content)
      expect(response.parsed_body['mfa_required']).to be(true)
      expect(response.parsed_body['mfa_token']).to be_present
      expect(response.parsed_body).not_to have_key('user')
    end

    context 'com o mfa_token' do
      let(:mfa_token) { Mfa::TokenService.new(user: user).generate_token }

      # A conferência do TOTP é do Mfa::AuthenticationService (coberta no fork) e exige chaves de
      # criptografia que o ambiente de teste não tem; aqui vale a fiação do endpoint.
      def stub_code(valid)
        allow(Mfa::AuthenticationService).to receive(:new)
          .with(user: user, otp_code: '123456', backup_code: nil)
          .and_return(instance_double(Mfa::AuthenticationService, authenticate: valid))
      end

      it 'devolve a identidade com o código certo' do
        stub_code(true)
        login({ mfa_token: mfa_token, otp_code: '123456' })

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['user']['id']).to eq(user.id)
      end

      it 'recusa código errado' do
        key = "captador:mfa_errors:#{user.id}"
        expect(Redis::Alfred).to receive(:incr).with(key).and_return(1)
        expect(Redis::Alfred).to receive(:expire).with(key, 15.minutes.to_i)
        stub_code(false)
        login({ mfa_token: mfa_token, otp_code: '123456' })

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body['error_code']).to eq('invalid_credentials')
      end

      it 'recusa mfa_token inválido ou vencido' do
        login({ mfa_token: 'invalido', otp_code: '123456' })

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body['error_code']).to eq('mfa_token_invalid')
      end


      it 'bloqueia novos códigos quando o usuário acumulou dez erros' do
        key = "captador:mfa_errors:#{user.id}"
        allow(Redis::Alfred).to receive(:get).with(key).and_return('10')
        expect(Mfa::AuthenticationService).not_to receive(:new)

        login({ mfa_token: mfa_token, otp_code: '123456' })

        expect(response).to have_http_status(:too_many_requests)
      end

      it 'não revela que a senha e o código de quem está fora da conta são válidos' do
        outsider = create(:user, account: create(:account))
        token = Mfa::TokenService.new(user: outsider).generate_token
        allow(Mfa::AuthenticationService).to receive(:new)
          .with(user: outsider, otp_code: '123456', backup_code: nil)
          .and_return(instance_double(Mfa::AuthenticationService, authenticate: true))

        login({ mfa_token: token, otp_code: '123456' })

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body['error_code']).to eq('invalid_credentials')
      end
    end
  end

  describe 'Rack::Attack' do
    def discriminator(name, body)
      env = Rack::MockRequest.env_for(path, method: 'POST', input: body.to_json, 'CONTENT_TYPE' => 'application/json')
      Rack::Attack.throttles.fetch(name).block.call(Rack::Attack::Request.new(env))
    end

    it 'limita a senha por e-mail e o passo do código pelo token e pelo e-mail do usuário' do
      mfa_token = Mfa::TokenService.new(user: user).generate_token
      expect(discriminator('captador_login/email', { email: ' Maria@Simplex.com ', password: 'x' })).to eq('maria@simplex.com')
      expect(discriminator('captador_login/email', { mfa_token: 'abc', otp_code: '1' })).to be_nil
      expect(discriminator('captador_login/mfa_token', { mfa_token: 'abc', otp_code: '1' })).to eq('abc')
      expect(discriminator('captador_login/mfa_email', { mfa_token: mfa_token, otp_code: '1' })).to eq(user.email.downcase)
    end
  end
end
