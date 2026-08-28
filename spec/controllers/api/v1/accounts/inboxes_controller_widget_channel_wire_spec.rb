require 'rails_helper'

# Bloco 3.06 — o ROUND-TRIP do escopo `channel` da tela de configuracao do widget.
#
# O dispatch nao prova nada. `useInboxWidgetConfig#save` manda `formData: false`,
# ou seja, JSON cru: `buildInboxData` — o unico lugar que traduzia
# `selectedFeatureFlags` para `channel[selected_feature_flags][]` — nao esta no
# caminho. Um spec de front que so olha o que foi despachado fica verde com o
# nome errado; o servidor descarta a chave no `permit`, responde 200, e a tela
# mostra "salvo" sobre um banco que nao mudou.
#
# Por isso este spec LE O MAPA DO FRONT e usa o `path` que esta la como chave da
# requisicao: se o nome de fio divergir de `Channel::WebWidget::EDITABLE_ATTRS`,
# o round-trip cai aqui, no lado que tem banco.
RSpec.describe 'Widget config — nomes de fio do escopo channel', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_widget, account: account) }
  let(:inbox) { channel.inbox }
  let(:base_url) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}" }

  def mapa_do_front
    File.read(
      Rails.root.join('app/javascript/dashboard/routes/dashboard/settings/inbox/widget/composables/widgetConfigFields.js')
    )
  end

  # Os descritores de `WIDGET_CONFIG_FIELDS`, um hash por campo. A abertura e
  # ancorada em `\n  {\n` — chave sozinha na indentacao 2 — e nao em qualquer
  # `{`: os comentarios do mapa citam nomes de chave entre chaves, e um `{` de
  # comentario abriria uma captura torta que ainda assim casaria os `key:`
  # seguintes. O fechamento e `\n  }`; os objetos internos dos `read:` fecham
  # com indentacao maior e por isso nao encerram a captura.
  def descritores
    bloco = mapa_do_front[/export const WIDGET_CONFIG_FIELDS = \[(.*?)\n\];/m, 1]
    bloco.scan(/\n {2}\{\n(.*?)\n {2}\}/m).flatten.map do |corpo|
      { key: corpo[/key: '([^']+)'/, 1], scope: corpo[/scope: '([^']+)'/, 1], path: corpo[/path: '([^']+)'/, 1] }
    end
  end

  def caminho(key)
    descritores.find { |d| d[:key] == key }[:path]
  end

  def patch_channel(atributos)
    patch base_url, headers: admin.create_new_auth_token, params: { channel: atributos }, as: :json
  end

  describe 'a leitura do mapa do front' do
    it 'achou os descritores — senao todo teste abaixo passaria no vacuo' do
      expect(descritores.size).to be >= 12
      expect(descritores.map { |d| d[:key] }).to include('featureFlags', 'widgetColor', 'appearance')
      expect(descritores.find { |d| d[:key] == 'featureFlags' }[:scope]).to eq('channel')
    end
  end

  describe 'PATCH com o `path` que a tela usa' do
    it 'grava as feature flags e le de volta do BANCO' do
      # o padrao de fabrica e 7 (attachments + emoji_picker + end_conversation):
      # o alvo tira uma e poe outra, entao nem adicao nem remocao passa de graca
      expect(channel.selected_feature_flags).to match_array(%i[attachments emoji_picker end_conversation])

      patch_channel(caminho('featureFlags') => %w[attachments allow_mobile_webview])

      expect(response).to have_http_status(:success)
      expect(channel.reload.selected_feature_flags).to match_array(%i[attachments allow_mobile_webview])
    end

    it 'desmarcar a ultima flag realmente esvazia a coluna' do
      patch_channel(caminho('featureFlags') => [])

      expect(response).to have_http_status(:success)
      expect(channel.reload.selected_feature_flags).to eq([])
      expect(channel.reload.feature_flags).to eq(0)
    end

    it 'o GET seguinte devolve o que foi gravado — o eco nao desmarca sozinho' do
      patch_channel(caminho('featureFlags') => %w[emoji_picker])

      get base_url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['selected_feature_flags']).to match_array(%w[emoji_picker])
    end

    it 'todo `path` de escopo channel do mapa esta em EDITABLE_ATTRS' do
      permitidos = Channel::WebWidget::EDITABLE_ATTRS.flat_map { |attr| attr.is_a?(Hash) ? attr.keys : attr }.map(&:to_s)
      do_front = descritores.select { |d| d[:scope] == 'channel' }.map { |d| d[:path] }

      expect(do_front).not_to be_empty
      expect(do_front - permitidos).to eq([])
    end
  end

  # A condicao ruim FORCADA. Sem ela, os testes acima ficariam verdes tambem
  # numa base onde o servidor aceitasse qualquer nome — e o que se quer provar e
  # justamente que o nome errado nao da erro nenhum, que e o que tornou o
  # defeito invisivel por tanto tempo.
  describe 'o que acontece com o nome errado' do
    it 'camelCase e descartado em SILENCIO: 200, nenhuma mudanca no banco' do
      antes = channel.selected_feature_flags

      patch_channel('selectedFeatureFlags' => %w[allow_mobile_webview])

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['id']).to eq(inbox.id)
      expect(channel.reload.selected_feature_flags).to match_array(antes)
    end
  end
end
