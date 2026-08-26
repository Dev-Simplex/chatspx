# frozen_string_literal: true

# BLOCO 4.05 — a ponta a ponta do lado do servidor: o texto sai da campanha e chega ao HTML
# que o host vai ler.
#
# O spec de modelo (`spec/models/channel/web_widget_teaser_spec.rb`) prova a precedência; o
# spec de SDK (`app/javascript/sdk/specs/teaserCampanha.spec.js`) prova o que o host faz com
# o valor. Falta o elo do meio, que é onde a junção estava rompida: o payload de boot.
# Editar a campanha não mudava o que o visitante via porque a campanha simplesmente NÃO
# viajava — `chatwootWebChannel` levava `welcomeTagline`, de outra tela.
#
# ESTE SPEC ACUSA: ele renderiza a página de verdade, muda o texto da campanha, renderiza de
# novo e exige que o HTML tenha mudado junto. Um exemplo que só conferisse "existe a chave
# teaserText" ficaria verde com a chave levando a tagline eterna.
require 'rails_helper'

RSpec.describe 'GET /widget — o texto do teaser no payload de boot', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) do
    create(:channel_widget, account: account, welcome_tagline: 'Estamos online', welcome_title: 'Ola!')
  end
  let(:inbox) { web_widget.inbox }

  def boot_payload
    get widget_url(website_token: web_widget.website_token)
    expect(response).to be_successful
    response.body
  end

  it 'leva a mensagem da campanha vinculada, e não a tagline da inbox' do
    create(:campaign, account: account, inbox: inbox, message: 'Frete gratis hoje')

    corpo = boot_payload

    expect(corpo).to include('teaserText: "Frete gratis hoje"')
    # A tagline continua no payload (o painel a usa na tela inicial) — o que não pode é ela
    # ser o texto do teaser.
    expect(corpo).to include('welcomeTagline: "Estamos online"')
    expect(corpo).not_to include('teaserText: "Estamos online"')
  end

  it 'editar a campanha muda o HTML do boot seguinte — o aceite do 4.05' do
    campanha = create(:campaign, account: account, inbox: inbox, message: 'Frete gratis hoje')

    expect(boot_payload).to include('teaserText: "Frete gratis hoje"')

    campanha.update!(message: 'Ultimas unidades com 20% off')

    corpo = boot_payload
    expect(corpo).to include('teaserText: "Ultimas unidades com 20% off"')
    expect(corpo).not_to include('Frete gratis hoje')
  end

  it 'sem campanha, o teaser recebe a tagline — a inbox nunca fica com o balão mudo' do
    expect(boot_payload).to include('teaserText: "Estamos online"')
  end

  it 'texto de campanha com aspas e tag não quebra o literal JavaScript' do
    # O valor entra dentro de `<script>` com `.html_safe`. O cliente escreve o texto do
    # convite na Tela 2, então isto é entrada de usuário: uma aspa fecharia a string e um
    # `</script>` fecharia o bloco inteiro, derrubando o boot do widget no site do cliente.
    create(:campaign, account: account, inbox: inbox,
                      message: %(Diga "oi" </script><script>alert(1)</script>))

    corpo = boot_payload

    expect(corpo).to include('\"oi\"')
    expect(corpo).to include('teaserText:')
    # `to_json` do Rails escapa `<`, `>` e `&`; a tag literal não pode aparecer no payload.
    expect(corpo).not_to include('</script><script>alert(1)')
    expect(corpo).to include('</script>')
  end
end
