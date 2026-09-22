require 'rails_helper'

RSpec.describe PublicController do
  controller do
    before_action :ensure_custom_domain_request

    def index
      head :ok
    end
  end

  it 'directs visitors with an unregistered domain to their administrator' do
    request.host = 'unknown.example.org'
    allow(DomainHelper).to receive(:chatwoot_domain?).with(request.host).and_return(false)

    get :index

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body['error']).to include('contact your administrator')
    expect(response.body).not_to include('chatwoot.com', 'API key')
  end
end
