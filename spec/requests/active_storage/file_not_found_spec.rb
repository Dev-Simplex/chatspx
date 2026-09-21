require 'rails_helper'

# N-04: a miniatura de uma midia recem-chegada pode ser pedida antes de o arquivo chegar ao disco. O Rails
# respondia 500 (a issue mais frequente do GlitchTip); agora e 404 sem cache, para o front tentar de novo e
# nada ficar guardado no navegador.
RSpec.describe 'ActiveStorage com o arquivo fora do disco', type: :request do
  let(:message) { create(:message) }
  let(:attachment) do
    message.attachments.create!(account_id: message.account_id, file_type: :image,
                                file: Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/avatar.png'), 'image/png'))
  end

  it 'answers 404 with no-store instead of 500 when the representation is asked before the file exists' do
    blob = attachment.file.blob
    blob.service.delete(blob.key)

    variacao = ActiveStorage::Variation.encode(resize_to_fill: [250, nil])
    get rails_blob_representation_path(blob.signed_id, variacao, blob.filename)

    expect(response).to have_http_status(:not_found)
    expect(response.headers['Cache-Control']).to eq('no-store')
  end
end
