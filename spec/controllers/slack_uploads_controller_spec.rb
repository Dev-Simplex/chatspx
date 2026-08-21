require 'rails_helper'

RSpec.describe SlackUploadsController do
  # `avatar_url` monta uma URL ABSOLUTA a partir de `FRONTEND_URL` e o controller faz
  # `redirect_to` nela. Em producao isso e same-host — quem chama e o proprio dominio de
  # `FRONTEND_URL` —, entao o Rails permite. No teste o host e sempre `test.host` e nunca
  # coincide com a `FRONTEND_URL` real da maquina: o Rails levanta `UnsafeRedirectError`.
  #
  # Sem fixar isto o spec so passa onde `FRONTEND_URL` esta AUSENTE, caso em que a URL vira
  # relativa por acidente — ou seja, a configuracao de producao (variavel setada, redirect
  # absoluto) nunca era exercitada. Apontando `FRONTEND_URL` para o host do proprio teste,
  # reproduzimos a forma de producao em vez de depender da maquina nao ter a variavel.
  around do |example|
    with_modified_env FRONTEND_URL: 'http://test.host' do
      example.run
    end
  end

  describe 'GET #show' do
    context 'when a valid blob key is provided' do
      file = Rack::Test::UploadedFile.new('spec/assets/avatar.png', 'image/png')
      blob = ActiveStorage::Blob.create_and_upload! io: file, filename: 'avatar.png'

      it 'redirects to the blob service URL' do
        get :show, params: { blob_key: blob.key }
        redirect_path = response.location
        expect(redirect_path).to match(%r{rails/active_storage/representations/redirect/.*/avatar.png})
      end
    end

    context 'when an invalid blob key is provided' do
      it 'returns contact default avatar url if the user is contact' do
        get :show, params: { key: 'invalid_key', sender_type: 'contact' }
        redirect_path = response.location
        expect(redirect_path).to match(%r{integrations/slack/contact.png})
      end

      it 'returns agent default avatar url if the user is agent' do
        get :show, params: { key: 'invalid_key', sender_type: 'user' }
        redirect_path = response.location
        expect(redirect_path).to match(%r{integrations/slack/user.png})
      end
    end

    context 'when no blob key is provided' do
      it 'returns contact default avatar url if the user is contact' do
        get :show, params: { sender_type: 'contact' }
        redirect_path = response.location
        expect(redirect_path).to match(%r{integrations/slack/contact.png})
      end

      it 'returns agent default avatar url if the user is agent' do
        get :show, params: { sender_type: 'user' }
        redirect_path = response.location
        expect(redirect_path).to match(%r{integrations/slack/user.png})
      end
    end
  end
end
