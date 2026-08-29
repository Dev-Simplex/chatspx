require 'rails_helper'

# Bloco 3.19 — a JUNCAO: `permit`, upload, recusa e o que sai no payload do widget.
#
# O spec de modelo prova a regra; este prova que ela e alcancavel pela porta que a tela usa. Foi
# exatamente essa distancia que fez o modo `image` viver meses gravavel e inalcancavel.
RSpec.describe 'Inbox launcher icon API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }
  let(:base_url) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}" }

  # PNG 1x1 de verdade, escrito num arquivo temporario. Nao entra asset novo no repositorio: `*.png`
  # esta no `.gitignore` e o `git add` o pularia em silencio.
  def tiny_png_upload
    file = Tempfile.new(['launcher', '.png'])
    file.binmode
    file.write(
      Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==')
    )
    file.rewind
    Rack::Test::UploadedFile.new(file.path, 'image/png')
  end

  def upload(file)
    patch base_url, headers: admin.create_new_auth_token, params: { launcher_icon_image: file }
  end

  describe 'o upload do byte' do
    it 'aceita uma imagem dentro do teto e devolve o anexo' do
      upload(tiny_png_upload)

      expect(response).to have_http_status(:success)
      expect(inbox.reload.launcher_icon_image).to be_attached
    end

    it 'recusa com 422 uma imagem acima de 20 KB, dizendo o motivo em pt-BR' do
      # 27.270 bytes — o avatar que a suite ja carrega. Sem asset novo, e acima do teto de verdade.
      upload(fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png'))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('20480').and include('baixado em toda página')
      expect(inbox.reload.launcher_icon_image).not_to be_attached
    end

    it 'nao aceita de agente: quem troca a cara da inbox e administrador' do
      patch base_url, headers: agent.create_new_auth_token, params: { launcher_icon_image: tiny_png_upload }

      # Pundit nega com 401 nesta base — so o corpo distingue "nao entrou" de "policy negou".
      expect(response).to have_http_status(:unauthorized)
      expect(inbox.reload.launcher_icon_image).not_to be_attached
    end
  end

  describe 'o modo e o payload que o site do cliente recebe' do
    before do
      upload(tiny_png_upload)
      patch base_url,
            headers: admin.create_new_auth_token,
            params: { additional_attributes: { widget_appearance: { launcher_icon: 'image' } } },
            as: :json
    end

    it 'grava o modo e devolve `{mode, url}` resolvido, com o byte no NOSSO dominio' do
      expect(response).to have_http_status(:success)

      icon = inbox.reload.resolved_widget_appearance['launcher_icon']
      expect(icon['mode']).to eq('image')
      expect(icon['url']).to start_with("#{ENV.fetch('FRONTEND_URL', nil)}/rails/active_storage/blobs/proxy/")
    end

    it 'o mesmo `{mode, url}` sai no config que o widget busca' do
      post "/api/v1/widget/config?website_token=#{web_widget.website_token}", as: :json

      expect(response).to have_http_status(:success)
      icon = response.parsed_body.dig('website_channel_config', 'widget_appearance', 'launcher_icon')
      expect(icon['url']).to eq(inbox.reload.launcher_icon_image_url)
    end

    it 'o byte e servido pela nossa aplicacao, com cache longo — nenhuma CDN externa' do
      get URI.parse(inbox.reload.launcher_icon_image_url).path

      expect(response).to have_http_status(:success)
      # "cache longo" MEDIDO, e nao "tem um max-age": um `max-age=60` passaria por qualquer
      # asseracao de presenca e faria o navegador do visitante rebuscar o icone o dia inteiro.
      cache_control = response.headers['Cache-Control'].to_s
      expect(cache_control).to include('public')
      expect(cache_control[/max-age=(\d+)/, 1].to_i).to be >= 1.year.to_i
      expect(response.body.bytesize).to be <= WidgetAppearanceSchema::MAX_LAUNCHER_ICON_BYTES
    end

    it 'apagar o icone tira o byte E o modo, para nao sobrar "foto" sem foto' do
      delete "#{base_url}/launcher_icon", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(inbox.reload.launcher_icon_image).not_to be_attached
      expect(inbox.widget_appearance['launcher_icon']).to eq('default')
    end
  end

  describe 'a CDN externa (aceite 4)' do
    it 'e recusada com 422 e com a razao, em vez de aceita e descartada na leitura' do
      upload(tiny_png_upload)
      patch base_url,
            headers: admin.create_new_auth_token,
            params: { additional_attributes: { widget_appearance: { launcher_icon: { mode: 'image', url: 'https://cdn.evil/x.png' } } } },
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('nosso próprio domínio')
      expect(inbox.reload.widget_appearance).to be_nil
    end
  end
end
