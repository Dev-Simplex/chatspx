# frozen_string_literal: true

require 'rails_helper'

# Bloco 5.08 — o ACEITE medido pelos endpoints reais:
#
#   "Visitante que chega por anuncio, navega 5 paginas e so entao abre o chat: a conversa
#    nasce com o `first_utm_source` e o `gclid` certos."
#
# O coletor do SDK (`app/javascript/sdk/tracking/`) entrega a origem por DOIS caminhos, e o
# aceite so fecha se os dois chegarem:
#
#   · `first_*`  -> `PATCH /api/v1/widget/contact`                (contato, write-once)
#   · `last_*`   -> `custom_attributes` do POST que cria a conversa, e depois
#                   `POST /api/v1/widget/conversations/set_custom_attributes` nas paginas
#                   seguintes
#
# O segundo caminho era uma SUBSTITUICAO: o `update!` reescrevia o objeto inteiro, e as
# chaves que o proprio servidor tinha gravado no `before_create` da conversa
# (`Tracking::OriginRecorder`, bloco 1.19) — `last_page_host`, `last_page_path`,
# `last_origin_kind` — sumiam na primeira escrita vinda do site. Sao justamente as chaves por
# onde `Tracking::OriginReport` agrupa.
RSpec.describe 'origem da conversa (bloco 5.08)', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }
  let(:contact) { create(:contact, account: account, email: nil, phone_number: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, hmac_verified: false) }
  let(:token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: inbox.id }).generate_token
  end

  # A pagina do anuncio. O widget manda `document.location.href` em `referer_url`; e dela que
  # o `Tracking::OriginRecorder` deriva os `last_*` no `before_create` da conversa.
  let(:pagina_do_anuncio) { 'https://loja.exemplo.com/oferta?utm_source=google&utm_medium=cpc&gclid=CjwKC-abc123' }

  def coletor_entrega_ao_contato(attrs)
    patch '/api/v1/widget/contact',
          params: { website_token: web_widget.website_token, custom_attributes: attrs },
          headers: { 'X-Auth-Token' => token },
          as: :json
  end

  def prechat_cria_conversa(custom_attributes)
    post '/api/v1/widget/conversations',
         params: { website_token: web_widget.website_token,
                   contact: { name: 'Visitante', email: 'visitante@exemplo.com' },
                   custom_attributes: custom_attributes,
                   message: { content: 'quero um orcamento', referer_url: pagina_do_anuncio } },
         headers: { 'X-Auth-Token' => token },
         as: :json
  end

  def site_escreve_na_conversa(attrs)
    post '/api/v1/widget/conversations/set_custom_attributes',
         params: { website_token: web_widget.website_token, custom_attributes: attrs },
         headers: { 'X-Auth-Token' => token },
         as: :json
  end

  describe 'a conversa NASCE com a origem (caminho do pre-chat)' do
    before do
      # 1. o coletor, no boot do widget, carimba o contato com o toque da PRIMEIRA visita
      coletor_entrega_ao_contato({ first_utm_source: 'google', first_utm_medium: 'cpc', first_origin_kind: 'busca_paga' })
      # 2. cinco paginas depois, o visitante preenche o pre-chat: a conversa nasce levando o
      #    que estava pendente no widget (`pendingCustomAttributes`) junto do que ele digitou
      prechat_cria_conversa({ last_utm_source: 'google', last_gclid: 'CjwKC-abc123', order_id: '12345' })
    end

    let(:conversa) { Conversation.where(contact_inbox: contact_inbox).last }

    it 'grava o `first_utm_source` no contato' do
      expect(response).to have_http_status(:success)
      expect(contact.reload.custom_attributes).to include('first_utm_source' => 'google')
    end

    it 'grava o `gclid` na conversa que acabou de nascer' do
      expect(conversa).to be_present, 'a conversa nem foi criada: o exemplo mediria nada'
      expect(conversa.custom_attributes).to include('last_gclid' => 'CjwKC-abc123')
    end

    it 'nao troca o que o pre-chat digitou pelo que o coletor mandou' do
      expect(conversa.custom_attributes).to include('order_id' => '12345')
    end

    # O `before_create` do 1.19 escreve na MESMA chave `custom_attributes` que o payload do
    # widget preenche. Se um dos dois lados vencesse, o relatorio de origem perderia o eixo.
    it 'convive com o que o servidor derivou do referer' do
      expect(conversa.custom_attributes).to include('last_page_host' => 'loja.exemplo.com')
      expect(conversa.custom_attributes['last_origin_kind']).to be_present
    end
  end

  describe 'a 2a pagina NAO apaga a origem' do
    before do
      prechat_cria_conversa({ last_utm_source: 'google', last_gclid: 'CjwKC-abc123' })
    end

    let(:conversa) { Conversation.where(contact_inbox: contact_inbox).last }

    it 'as chaves gravadas pelo servidor sobrevivem a escrita vinda do site' do
      derivadas = conversa.custom_attributes.slice('last_page_host', 'last_page_path', 'last_origin_kind')
      expect(derivadas.keys).to contain_exactly('last_page_host', 'last_page_path', 'last_origin_kind'),
                                'o servidor nao gravou as chaves derivadas: o exemplo mediria nada'

      # exatamente o que o coletor reenvia na pagina seguinte — sem as derivadas, que ele
      # nunca teve
      site_escreve_na_conversa({ last_utm_source: 'google', last_gclid: 'CjwKC-abc123', fbp: 'fb.1.1700000000.42' })

      expect(response).to have_http_status(:success)
      expect(conversa.reload.custom_attributes).to include(derivadas)
      expect(conversa.custom_attributes).to include('fbp' => 'fb.1.1700000000.42')
    end

    it 'o que o pre-chat digitou tambem sobrevive' do
      conversa.update!(custom_attributes: conversa.custom_attributes.merge('order_id' => '12345'))

      site_escreve_na_conversa({ last_utm_source: 'google' })

      expect(conversa.reload.custom_attributes).to include('order_id' => '12345')
    end

    # CONTROLE NEGATIVO. Sem ele os dois exemplos acima passariam num mundo onde
    # `set_custom_attributes` nao grava nada nunca.
    it 'continua gravando o que o site mandou' do
      site_escreve_na_conversa({ last_utm_source: 'bing' })

      expect(conversa.reload.custom_attributes).to include('last_utm_source' => 'bing')
    end

    # O endpoint deixou de ser substituicao — entao a REMOCAO tem de continuar existindo por
    # onde ela sempre existiu, senao o site perde a capacidade de apagar o que escreveu.
    it 'a remocao continua sendo pelo endpoint de exclusao' do
      site_escreve_na_conversa({ cupom: 'BLACK' })

      post '/api/v1/widget/conversations/destroy_custom_attributes',
           params: { website_token: web_widget.website_token, custom_attribute: ['cupom'] },
           headers: { 'X-Auth-Token' => token },
           as: :json

      expect(conversa.reload.custom_attributes).not_to have_key('cupom')
      expect(conversa.custom_attributes).to include('last_gclid' => 'CjwKC-abc123')
    end
  end
end
