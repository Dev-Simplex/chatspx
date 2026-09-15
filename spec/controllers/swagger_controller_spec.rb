require 'rails_helper'

describe '/swagger', type: :request do
  describe 'GET /swagger' do
    it 'renders swagger index.html' do
      get '/swagger'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('api-reference')
      expect(response.body).to include('/swagger.json')
    end
  end

  describe 'GET /swagger/*path' do
    it 'renders the explicit index.html path' do
      get '/swagger/index.html'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('api-reference')
    end

    it 'serves swagger.json without Basic Auth' do
      get '/swagger/swagger.json'

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to have_key('openapi')
    end

    it 'returns not found for a missing file' do
      get '/swagger/v1/swagger.json'

      expect(response).to have_http_status(:not_found)
    end

    it 'returns not found for a directory' do
      get '/swagger/paths'

      expect(response).to have_http_status(:not_found)
    end
  end
end
