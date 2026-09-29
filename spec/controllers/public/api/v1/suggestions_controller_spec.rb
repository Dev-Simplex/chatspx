require 'rails_helper'

RSpec.describe 'Public suggestions API (SUG-02)', type: :request do
  let(:url) { '/public/api/v1/suggestions' }
  let(:campos) { { name: 'Maria', company: 'Imobiliaria X', content: 'Filtro por bairro na lista.' } }

  it 'grava a sugestao do link publico, sem conta nem usuario' do
    expect { post url, params: campos }.to change(Suggestion, :count).by(1)

    expect(response).to have_http_status(:created)
    suggestion = Suggestion.last
    expect(suggestion).to have_attributes(source: 'public_link', status: 'nova', name: 'Maria', company: 'Imobiliaria X',
                                          account_id: nil, user_id: nil)
  end

  it 'aceita foto no anexo' do
    foto = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/avatar.png'), 'image/png')

    post url, params: campos.merge(media: foto)

    expect(response).to have_http_status(:created)
    expect(Suggestion.last.media).to be_attached
  end

  it 'recusa anexo que nao e foto nem video' do
    pdf = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/attachment.pdf'), 'application/pdf')

    expect { post url, params: campos.merge(media: pdf) }.not_to change(Suggestion, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'finge sucesso para o bot que preenche o honeypot, sem gravar' do
    expect { post url, params: campos.merge(website: 'http://spam') }.not_to change(Suggestion, :count)
    expect(response).to have_http_status(:ok)
  end

  it 'devolve 422 com as mensagens quando faltam os obrigatorios' do
    expect { post url, params: { content: '' } }.not_to change(Suggestion, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to be_present
  end

  it 'nao expoe leitura publica' do
    create(:suggestion, source: :public_link, name: 'Maria', company: 'X', content: 'segredo')

    get url

    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('segredo')
  end
end
