require 'rails_helper'

# Bloco 1.19 — parser de origem (C0), prospectivo (D6).
#
# O aceite é end-to-end de propósito: o visitante abre o chat numa URL de campanha e o atendente
# tem que ver a origem no painel NA MESMA SESSÃO. Testar só o parser provaria que sabemos ler uma
# query string, não que o produto passou a saber de onde veio o lead.
RSpec.describe 'Origem da conversa pelo widget (1.19)', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, email: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
  let(:payload) { { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id } }
  let(:token) { Widget::TokenService.new(payload: payload).generate_token }

  before { create(:inbox_member, user: admin, inbox: web_widget.inbox) }

  def abrir_chat_em(referer_url)
    post '/api/v1/widget/conversations',
         headers: { 'X-Auth-Token' => token },
         params: {
           website_token: web_widget.website_token,
           contact: { name: 'visitante' },
           message: { content: 'quero um orçamento', referer_url: referer_url }
         },
         as: :json

    expect(response).to have_http_status(:success)
    response.parsed_body['id']
  end

  # Lê do BANCO, consulta nova — não do objeto que o controller deixou em memória.
  def origem_no_banco(display_id)
    Conversation.where(account_id: account.id, display_id: display_id).pick(:custom_attributes)
  end

  def painel_do_agente(display_id)
    get "/api/v1/accounts/#{account.id}/conversations/#{display_id}",
        headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    response.parsed_body
  end

  describe 'aceite (1) — os campos aparecem no painel na mesma sessão' do
    it 'grava last_* na conversa e o painel do agente os devolve' do
      display_id = abrir_chat_em('https://loja.exemplo.com.br/tenis?utm_source=google&gclid=Cj0KCQ')

      expect(origem_no_banco(display_id)).to include(
        'last_utm_source' => 'google',
        'last_gclid' => 'Cj0KCQ',
        'last_page_host' => 'loja.exemplo.com.br',
        'last_page_path' => '/tenis',
        'last_origin_kind' => 'busca_paga'
      )

      atributos = painel_do_agente(display_id)['custom_attributes']
      expect(atributos['last_utm_source']).to eq('google')
      expect(atributos['last_gclid']).to eq('Cj0KCQ')
      expect(atributos['last_origin_kind']).to eq('busca_paga')
    end

    it 'as definições existem, então o painel sabe o nome e o tipo de cada campo' do
      abrir_chat_em('https://loja.exemplo.com.br/tenis?utm_source=google&gclid=Cj0KCQ')

      get "/api/v1/accounts/#{account.id}/custom_attribute_definitions",
          params: { attribute_model: 'conversation_attribute' },
          headers: admin.create_new_auth_token, as: :json

      definicoes = response.parsed_body.index_by { |d| d['attribute_key'] }
      expect(definicoes['last_utm_source']['attribute_display_name']).to eq('Origem da campanha (última)')
      expect(definicoes['last_origin_kind']['attribute_display_type']).to eq('list')
    end

    it 'a URL só mal escapada, que o 1.20 recupera, também é parseada' do
      display_id = abrir_chat_em('https://loja.exemplo.com.br/produtos/tenis nike?utm_source=google&utm_medium=cpc')

      expect(origem_no_banco(display_id)).to include(
        'last_utm_source' => 'google', 'last_utm_medium' => 'cpc', 'last_origin_kind' => 'busca_paga'
      )
    end

    it 'conversa sem referer não ganha chave de origem nenhuma' do
      display_id = abrir_chat_em('')

      expect(origem_no_banco(display_id).keys & Tracking::OriginAttributes.conversation_keys).to eq([])
    end
  end

  describe 'aceite (2) — a 2ª conversa não sobrescreve first_*' do
    it 'carimba o contato na primeira e o preserva na segunda' do
      abrir_chat_em('https://loja.exemplo.com.br/p?utm_source=google&utm_campaign=primeira&gclid=AAA')

      expect(contact.reload.custom_attributes).to include(
        'first_utm_source' => 'google', 'first_utm_campaign' => 'primeira', 'first_gclid' => 'AAA'
      )

      display_id2 = abrir_chat_em('https://loja.exemplo.com.br/p?utm_source=meta&utm_campaign=segunda&fbclid=BBB')

      # o contato mantém a PRIMEIRA origem...
      expect(contact.reload.custom_attributes).to include(
        'first_utm_source' => 'google', 'first_utm_campaign' => 'primeira', 'first_gclid' => 'AAA'
      )
      # ...e a chave que ainda não existia entra, porque write-once é por chave
      expect(contact.custom_attributes['first_fbclid']).to eq('BBB')
      # ...enquanto a conversa nova registra a origem NOVA
      expect(origem_no_banco(display_id2)).to include(
        'last_utm_source' => 'meta', 'last_utm_campaign' => 'segunda', 'last_origin_kind' => 'social'
      )
    end

    it 'não carimba first_* quando a visita não traz sinal de campanha' do
      abrir_chat_em('https://loja.exemplo.com.br/pagina-qualquer')

      expect(contact.reload.custom_attributes.keys & Tracking::OriginAttributes.contact_keys).to eq([])
    end

    it 'a campanha da segunda visita entra no contato quando a primeira não trouxe nenhuma' do
      abrir_chat_em('https://loja.exemplo.com.br/pagina-qualquer')
      abrir_chat_em('https://loja.exemplo.com.br/p?utm_source=google&utm_campaign=depois')

      expect(contact.reload.custom_attributes).to include(
        'first_utm_source' => 'google', 'first_utm_campaign' => 'depois'
      )
    end
  end

  describe 'aceite (3) — IA generativa é origem própria, não "direta"' do
    it 'conversa vinda do chatgpt.com aparece como ia_generativa' do
      display_id = abrir_chat_em('https://loja.exemplo.com.br/tenis?utm_source=chatgpt.com')

      expect(origem_no_banco(display_id)['last_origin_kind']).to eq('ia_generativa')
      expect(painel_do_agente(display_id)['custom_attributes']['last_origin_kind']).to eq('ia_generativa')
    end

    it 'perplexity, gemini e claude também têm origem própria' do
      %w[perplexity gemini.google.com claude.ai].each do |fonte|
        display_id = abrir_chat_em("https://loja.exemplo.com.br/p?utm_source=#{fonte}")
        expect(origem_no_banco(display_id)['last_origin_kind']).to eq('ia_generativa')
      end
    end

    it 'nenhuma conversa desta suíte recebe o rótulo "direta"' do
      ['https://loja.exemplo.com.br/p', 'https://loja.exemplo.com.br/p?utm_source=chatgpt.com', ''].each do |url|
        display_id = abrir_chat_em(url)
        expect(origem_no_banco(display_id)['last_origin_kind']).not_to eq('direta')
      end
    end
  end

  describe 'a origem não pode derrubar a conversa' do
    it 'conversa nasce mesmo quando o parser explode' do
      allow(Tracking::OriginParser).to receive(:new).and_raise(StandardError, 'boom')

      expect { abrir_chat_em('https://loja.exemplo.com.br/p?utm_source=google') }.not_to raise_error
      expect(Conversation.where(account_id: account.id).count).to eq(1)
    end
  end
end
