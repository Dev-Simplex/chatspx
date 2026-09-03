require 'rails_helper'

describe '/swagger', type: :request do
  describe 'GET /swagger' do
    it 'renders swagger index.html' do
      get '/swagger'
      expect(response).to have_http_status(:success)
      # ChatSPX: a doc e servida pelo Scalar (swagger/index.html), nao pelo ReDoc. O assert 'redoc'
      # ficou obsoleto quando o fork trocou o renderizador e vinha FALHANDO desde antes deste merge
      # (o mesmo par arquivo/assert existe em f26db6ee81). Ancora de conteudo real da pagina.
      expect(response.body).to include('@scalar/api-reference')
      expect(response.body).to include('/swagger/swagger.json')
    end

    it 'does not render files outside the swagger directory' do
      get '/swagger/%2Fetc%2Fpasswd'
      expect(response).to have_http_status(:not_found)
    end
  end

  # ChatSPX (A1 patch 3): o merge repôs o gate `if Rails.env.development? || Rails.env.test?` com
  # `else head :not_found`, o que fazia a doc da API não existir em produção e transformava
  # `authenticate_docs!` em código morto. Removido o gate, quem decide é o authenticate_docs!.
  # Estes casos exercitam o caminho de produção sem depender do ambiente do runner.
  describe 'GET /swagger outside development/test' do
    before do
      allow(Rails.env).to receive(:development?).and_return(false)
      allow(Rails.env).to receive(:test?).and_return(false)
    end

    it 'still hides the docs when SWAGGER_DOCS_PASSWORD is absent' do
      with_modified_env SWAGGER_DOCS_PASSWORD: nil do
        get '/swagger'
      end

      expect(response).to have_http_status(:not_found)
    end

    it 'asks for credentials when SWAGGER_DOCS_PASSWORD is set' do
      with_modified_env SWAGGER_DOCS_PASSWORD: 'segredo' do
        get '/swagger'
      end

      expect(response).to have_http_status(:unauthorized)
    end

    it 'serves the docs with the right credentials' do
      with_modified_env SWAGGER_DOCS_PASSWORD: 'segredo', SWAGGER_DOCS_USER: 'spxdocs' do
        get '/swagger', headers: { 'HTTP_AUTHORIZATION' => ActionController::HttpAuthentication::Basic.encode_credentials('spxdocs', 'segredo') }
      end

      expect(response).to have_http_status(:success)
      expect(response.body).to include('@scalar/api-reference')
    end

    it 'serves the machine-readable spec without credentials' do
      with_modified_env SWAGGER_DOCS_PASSWORD: 'segredo' do
        get '/swagger/swagger.json'
      end

      expect(response).to have_http_status(:success)
    end
  end
end
