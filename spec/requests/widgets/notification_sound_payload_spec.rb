# frozen_string_literal: true

require 'rails_helper'

# BLOCO 4.11 — o elo do meio, que e onde a junção estava rompida.
#
# O spec de modelo prova que a flag existe; o spec de SDK prova que o host so
# toca com ela em `enabledFeatures`. Falta o caminho de verdade: o administrador
# marca a caixa, a tela manda o PATCH, e o HTML que o visitante baixa passa a
# trazer a string que o SDK consulta.
#
# Aqui nada e dublado. O PATCH sobe pelo controller real, com `permit` real, e a
# leitura e do `widgets/show.html.erb` real — o mesmo `enabledFeatures` que
# `IframeEventHelper` devolve ao host no evento `loaded`.
RSpec.describe 'GET /widget — o som no payload de boot (4.11)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }

  # A string que o host procura. Escrita literal de proposito: e o contrato com
  # `IFrameHelper.isNotificationSoundEnabled`, e um `include` montado a partir da
  # constante do model passaria mesmo se os dois nomes divergissem.
  def enabled_features_do_boot
    get widget_url(website_token: web_widget.website_token)
    expect(response).to be_successful
    JSON.parse(response.body[/enabledFeatures: (\[.*?\])/, 1])
  end

  def patch_flags(flags)
    patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
          headers: admin.create_new_auth_token,
          params: { channel: { selected_feature_flags: flags } },
          as: :json
  end

  it 'inbox recem-criada nao leva `notification_sound` — o som nao existe sem opt-in' do
    expect(enabled_features_do_boot).not_to include('notification_sound')
  end

  it 'marcar a caixa faz a string chegar ao HTML que o visitante baixa' do
    patch_flags(%w[attachments emoji_picker notification_sound])

    expect(response).to have_http_status(:success)
    expect(enabled_features_do_boot).to include('notification_sound')
  end

  it 'desmarcar tira a string de volta — o desligar tambem tem de chegar' do
    patch_flags(%w[attachments notification_sound])
    expect(enabled_features_do_boot).to include('notification_sound')

    patch_flags(%w[attachments])

    expect(enabled_features_do_boot).not_to include('notification_sound')
  end

  it 'PATCH que nao menciona as flags nao apaga o som' do
    # O widget tem mais de uma tela salvando a mesma inbox. Se um PATCH que so
    # mexe no titulo zerasse `selected_feature_flags`, o cliente ligaria o som
    # numa aba e o perderia ao salvar outra — sem erro nenhum na tela.
    patch_flags(%w[attachments notification_sound])

    patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
          headers: admin.create_new_auth_token,
          params: { channel: { welcome_title: 'Ola!' } },
          as: :json
    expect(response).to have_http_status(:success)

    expect(enabled_features_do_boot).to include('notification_sound')
  end

  it 'e por inbox, nao por conta: ligar numa nao liga na outra' do
    outra = create(:channel_widget, account: account)
    patch_flags(%w[attachments notification_sound])

    get widget_url(website_token: outra.website_token)
    outras_features = JSON.parse(response.body[/enabledFeatures: (\[.*?\])/, 1])

    expect(enabled_features_do_boot).to include('notification_sound')
    expect(outras_features).not_to include('notification_sound')
  end
end
