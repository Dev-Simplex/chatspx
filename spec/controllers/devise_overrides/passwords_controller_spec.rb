require 'rails_helper'

# Em 31/08/2026 uma usuaria da Catatau ficou presa num laco: pediu recuperacao de senha 5 vezes e
# tentou 4 links diferentes, sempre um antigo. So existe UM token por pessoa, entao cada pedido novo
# mata os e-mails anteriores; como o erro era o literal 'Invalid token', em ingles e sem dizer o que
# fazer, cada tentativa frustrada virava outro pedido, que por sua vez matava o e-mail recem-chegado.
RSpec.describe 'DeviseOverrides::PasswordsController', type: :request do
  let(:user) { create(:user, password: 'Senha@Antiga1') }

  def token_valido
    user.send(:set_reset_password_token)
  end

  describe 'PUT /auth/password' do
    it 'troca a senha com um link valido' do
      put '/auth/password', params: { reset_password_token: token_valido,
                                      password: 'Nova@Senha1', password_confirmation: 'Nova@Senha1' }

      expect(response).to have_http_status(:success)
      expect(user.reload.valid_password?('Nova@Senha1')).to be(true)
    end

    # O caminho COMUM aqui, e nao a excecao.
    it 'recusa um link antigo depois de outro pedido de recuperacao' do
      antigo = token_valido
      token_valido # o segundo pedido sobrescreve o token do primeiro

      put '/auth/password', params: { reset_password_token: antigo,
                                      password: 'Nova@Senha1', password_confirmation: 'Nova@Senha1' }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    describe 'a mensagem de link invalido' do
      before do
        put '/auth/password', params: { reset_password_token: 'naoexiste',
                                        password: 'Nova@Senha1', password_confirmation: 'Nova@Senha1' }
      end

      it 'explica que o link e VELHO, em vez do antigo "Invalid token"' do
        expect(response.parsed_body['message']).to include('não é mais válido')
        expect(response.parsed_body['message']).not_to eq('Invalid token')
      end

      it 'diz o que fazer, senao a pessoa pede outro link e mata o que acabou de chegar' do
        expect(response.parsed_body['message']).to include('mais recente')
      end

      # O servidor nao sabe o idioma de um visitante deslogado; o navegador sabe. O `code` e o que
      # permite ao front traduzir na lingua de quem esta vendo.
      it 'manda um codigo estavel para o front traduzir' do
        expect(response.parsed_body['code']).to eq('reset_token_invalid')
      end
    end
  end

  # O e-mail de convite saia em INGLES com o assunto em portugues: o template de enterprise/
  # sobrepoe o de app/views/, e so o segundo tinha sido traduzido.
  describe 'e-mail de convite' do
    let(:conta) { create(:account) }
    let(:convidador) { create(:user, account: conta, role: :administrator) }
    # `skip_confirmation` e true por padrao na fabrica: sem desligar, o usuario nasce CONFIRMADO e o
    # e-mail cai no ramo de "entrar na conta", que nao e o do convite.
    let(:convidado) { create(:user, account: conta, role: :agent, skip_confirmation: false) }

    def corpo
      convidado.account_users.first.update!(inviter: convidador)
      Devise::Mailer.confirmation_instructions(convidado.reload, 'tok').body.to_s
    end

    it 'sai em portugues' do
      expect(corpo).to include('convidou você para usar')
      expect(corpo).to include('Confirmar minha conta')
    end

    it 'nao sai em ingles' do
      expect(corpo).not_to include('has invited you to try out')
      expect(corpo).not_to include('Confirm my account')
    end

    it 'avisa que so o link mais recente funciona' do
      expect(corpo).to include('mais recente')
    end
  end
end
