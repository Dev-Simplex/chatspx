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

      expect(origem_no_banco(display_id).keys.select { |chave| chave.start_with?('last_') }).to eq([])
    end
  end

  describe 'aceite (2) — a 2ª conversa não sobrescreve first_*' do
    it 'carimba o contato na primeira e o preserva na segunda' do
      abrir_chat_em('https://loja.exemplo.com.br/p?utm_source=google&utm_campaign=primeira&gclid=AAA')

      # o click id vai para a CONVERSA, não para o contato: `CONTACT_BASE_KEYS` não o inclui
      expect(contact.reload.custom_attributes).to include(
        'first_utm_source' => 'google', 'first_utm_campaign' => 'primeira', 'first_origin_kind' => 'busca_paga'
      )
      expect(contact.custom_attributes).not_to have_key('first_gclid')

      display_id2 = abrir_chat_em('https://loja.exemplo.com.br/p?utm_source=meta&utm_campaign=segunda&fbclid=BBB')

      # o contato mantém a PRIMEIRA origem...
      expect(contact.reload.custom_attributes).to include(
        'first_utm_source' => 'google', 'first_utm_campaign' => 'primeira', 'first_origin_kind' => 'busca_paga'
      )
      # ...enquanto a conversa nova registra a origem NOVA
      expect(origem_no_banco(display_id2)).to include(
        'last_utm_source' => 'meta', 'last_utm_campaign' => 'segunda', 'last_origin_kind' => 'social'
      )
    end

    it 'não carimba first_* quando a visita não traz sinal de campanha' do
      abrir_chat_em('https://loja.exemplo.com.br/pagina-qualquer')

      # prefixo inteiro, não `& contact_keys`: a intersecção não enxergaria uma chave gravada
      # FORA do catálogo, que é exatamente o defeito que este arquivo passou a guardar
      expect(contact.reload.custom_attributes.keys.select { |chave| chave.start_with?('first_') }).to eq([])
    end

    it 'a campanha da segunda visita entra no contato quando a primeira não trouxe nenhuma' do
      abrir_chat_em('https://loja.exemplo.com.br/pagina-qualquer')
      abrir_chat_em('https://loja.exemplo.com.br/p?utm_source=google&utm_campaign=depois')

      expect(contact.reload.custom_attributes).to include(
        'first_utm_source' => 'google', 'first_utm_campaign' => 'depois'
      )
    end
  end

  # A GUARDA QUE FALTAVA — e por que a antiga não servia.
  #
  # A asserção que existia interseccionava as chaves gravadas com `contact_keys`
  # (`escritas & definidas`). Essa conta é CEGA para o que está FORA do catálogo: `first_gclid`
  # nunca aparece na intersecção justamente porque não está definido — grava no banco e some da
  # vista, que é a mesma experiência de não existir [R19 §D.3]. E ela passa também quando NADA foi
  # escrito, porque `[] & lista` é `[]`.
  #
  # A pergunta certa é a inversa e não tem ponto cego: `escritas − definidas = vazio`. Toda chave
  # que o gravador escreve tem que ter definição, senão o painel não a mostra. Cada exemplo aqui
  # exige antes que o conjunto escrito NÃO seja vazio — sem isso a subtração passaria no vácuo.
  describe 'catálogo — nada é gravado fora do que o painel sabe mostrar' do
    def chaves_definidas(attribute_model)
      account.custom_attribute_definitions.where(attribute_model: attribute_model).pluck(:attribute_key)
    end

    def chaves_escritas(atributos, prefixo)
      atributos.keys.select { |chave| chave.start_with?(prefixo) }
    end

    let(:url_com_click_id) do
      'https://loja.exemplo.com.br/p?utm_source=google&utm_campaign=black&gclid=AAA&fbclid=BBB&ttclid=CCC'
    end

    it 'no contato: escritas − definidas = vazio, com três click ids na URL' do
      abrir_chat_em(url_com_click_id)

      escritas = chaves_escritas(contact.reload.custom_attributes, Tracking::OriginAttributes::CONTACT_PREFIX)
      # força a condição: sem isto a subtração abaixo também passaria com nada escrito
      expect(escritas).to include('first_utm_source', 'first_utm_campaign', 'first_origin_kind')

      expect(escritas - chaves_definidas('contact_attribute')).to eq([])
    end

    it 'na conversa: escritas − definidas = vazio, e lá o click id É do catálogo' do
      display_id = abrir_chat_em(url_com_click_id)

      escritas = chaves_escritas(origem_no_banco(display_id), Tracking::OriginAttributes::CONVERSATION_PREFIX)
      expect(escritas).to include('last_gclid', 'last_fbclid', 'last_ttclid', 'last_origin_kind')

      expect(escritas - chaves_definidas('conversation_attribute')).to eq([])
    end

    # O catálogo tem que segurar mesmo quando a fonte manda lixo — senão a garantia é do parser,
    # não do gravador, e o próximo campo entra pela porta lateral.
    it 'chave que o parser inventar não chega ao contato nem à conversa' do
      allow(Tracking::OriginParser).to receive(:new).and_return(
        instance_double(
          Tracking::OriginParser,
          attributes: { 'utm_source' => 'google', 'gclid' => 'AAA', 'chave_inventada' => 'X' }
        )
      )

      display_id = abrir_chat_em('https://loja.exemplo.com.br/p')

      contato = contact.reload.custom_attributes
      conversa = origem_no_banco(display_id)
      expect(chaves_escritas(contato, 'first_')).to include('first_utm_source')
      expect(chaves_escritas(conversa, 'last_')).to include('last_utm_source', 'last_gclid')

      expect(chaves_escritas(contato, 'first_') - chaves_definidas('contact_attribute')).to eq([])
      expect(chaves_escritas(conversa, 'last_') - chaves_definidas('conversation_attribute')).to eq([])
      expect(contato.keys + conversa.keys).not_to include(a_string_including('chave_inventada'))
    end

    # A mentira que o defeito produzia: contato carimbado como busca_paga na 1ª visita saindo com
    # o click id do Facebook da 2ª, porque write-once é por chave e a chave ainda não existia.
    it 'a 2ª visita não injeta click id no contato carimbado pela 1ª' do
      abrir_chat_em('https://loja.exemplo.com.br/p?utm_source=google&gclid=AAA')
      abrir_chat_em('https://loja.exemplo.com.br/p?utm_source=meta&fbclid=BBB')

      atributos = contact.reload.custom_attributes
      expect(atributos['first_origin_kind']).to eq('busca_paga')
      expect(atributos).not_to have_key('first_fbclid')
      expect(chaves_escritas(atributos, 'first_') - chaves_definidas('contact_attribute')).to eq([])
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

  # Achado da varredura de config (18/08): `create.json.jbuilder` do widget serializa
  # `custom_attributes` da conversa — que é exatamente onde o 1.19 grava os `last_*`. Ou seja: a
  # origem VOLTA para o visitante no payload de criação. É aceitável, e por um motivo estreito: o
  # dado é dele, veio da query string da própria página que ele abriu; não há informação nova ali.
  # O que NÃO pode voltar é dado cru não validado — esse fica em `additional_attributes`
  # (`referer_raw`, bloco 1.20), que o jbuilder não serializa.
  #
  # Este spec fixa a superfície: se alguém amanhã gravar em `custom_attributes` da conversa algo
  # que o visitante não deveria ver, ele fica vermelho e nomeia a chave.
  describe 'o que a origem devolve ao visitante no payload do widget' do
    it 'devolve os last_* (dado do próprio visitante) e NUNCA o referer cru' do
      post '/api/v1/widget/conversations',
           headers: { 'X-Auth-Token' => token },
           params: {
             website_token: web_widget.website_token,
             contact: { name: 'visitante' },
             message: { content: 'oi', referer_url: 'javascript:alert(document.cookie)' }
           },
           as: :json

      expect(response).to have_http_status(:success)
      corpo = response.body

      expect(corpo).not_to include('referer_raw')
      expect(corpo).not_to include('javascript:alert')
      expect(response.parsed_body).to have_key('custom_attributes')
    end

    it 'a origem visível ao visitante é só o que ele mesmo trouxe na URL' do
      display_id = abrir_chat_em('https://loja.exemplo.com.br/tenis?utm_source=google&gclid=Cj0KCQ')

      get "/api/v1/widget/conversations?website_token=#{web_widget.website_token}",
          headers: { 'X-Auth-Token' => token }, as: :json

      expect(response).to have_http_status(:success)
      expect(origem_no_banco(display_id)['last_utm_source']).to eq('google')
      # o que sai ao visitante não contém chave de origem que ele não tenha fornecido
      expect(response.body).not_to include('referer_raw')
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
