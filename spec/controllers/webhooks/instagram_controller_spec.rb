require 'rails_helper'

RSpec.describe 'Webhooks::InstagramController', type: :request do
  # A rota da verificacao e `get 'webhooks/instagram'` (routes.rb) — o mesmo caminho do POST,
  # como a Meta exige. Os tres exemplos batiam em `/webhooks/instagram/verify`, que NAO EXISTE.
  #
  # Os dois primeiros passavam por isso: esperavam 404 e recebiam o 404 da ROTA AUSENTE, nunca
  # chegando ao controller — token nenhum foi conferido em nenhum momento. Verde por ausencia de
  # sujeito. Os proprios NOMES ja diziam "returns 401", que e o que `MetaTokenVerifyConcern#verify`
  # devolve para token invalido; so a assercao e que tinha sido ajustada ao 404 acidental.
  describe 'GET /webhooks/instagram (verificacao da Meta)' do
    it 'returns 401 when valid params are not present' do
      get '/webhooks/instagram'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 401 when invalid params' do
      with_modified_env IG_VERIFY_TOKEN: '123456' do
        get '/webhooks/instagram', params: { 'hub.challenge' => '123456', 'hub.mode' => 'subscribe', 'hub.verify_token' => 'invalid' }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    it 'returns challenge when valid params' do
      with_modified_env IG_VERIFY_TOKEN: '123456' do
        get '/webhooks/instagram', params: { 'hub.challenge' => '123456', 'hub.mode' => 'subscribe', 'hub.verify_token' => '123456' }
        expect(response).to have_http_status(:success)
        expect(response.body).to include '123456'
      end
    end
  end

  describe 'POST /webhooks/instagram' do
    let!(:dm_params) { build(:instagram_message_create_event).with_indifferent_access }

    it 'call the instagram events job with the params' do
      allow(Webhooks::InstagramEventsJob).to receive(:perform_later)
      expect(Webhooks::InstagramEventsJob).to receive(:perform_later)

      instagram_params = dm_params.merge(object: 'instagram')
      post '/webhooks/instagram', params: instagram_params
      expect(response).to have_http_status(:success)
    end

    context 'when processing echo events' do
      let!(:echo_params) { build(:instagram_story_mention_event_with_echo).with_indifferent_access }

      it 'delays processing for echo events by 2 seconds' do
        job_double = class_double(Webhooks::InstagramEventsJob)
        allow(Webhooks::InstagramEventsJob).to receive(:set).with(wait: 2.seconds).and_return(job_double)
        allow(job_double).to receive(:perform_later)

        instagram_params = echo_params.merge(object: 'instagram')
        post '/webhooks/instagram', params: instagram_params
        expect(response).to have_http_status(:success)
        expect(Webhooks::InstagramEventsJob).to have_received(:set).with(wait: 2.seconds)
        expect(job_double).to have_received(:perform_later)
      end
    end
  end
end
