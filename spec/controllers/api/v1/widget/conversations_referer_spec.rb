require 'rails_helper'

# Bloco 1.20 — "parar de destruir o dado na escrita".
#
# Antes deste bloco, `Conversation#validate_referer_url` fazia
#   self['additional_attributes']['referer'] = nil unless url_valid?(...)
# e uma URL de site real só mal escapada (espaço cru, colchete cru no path) virava `nil` em
# silêncio — a conversa salvava normalmente e a origem do lead sumia antes de qualquer parser
# existir. Medição [M12]: 0 conversas com `referer` preenchido em 3.180.
#
# Este spec é a asserção (4) do aceite: grava uma conversa por cada uma das 3 formas de URL e lê
# os 3 valores **de volta do banco** — não do objeto em memória, não da resposta JSON.
RSpec.describe 'Widget conversations · saneamento do referer (1.20)', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:contact) { create(:contact, account: account, email: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
  let(:payload) { { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id } }
  let(:token) { Widget::TokenService.new(payload: payload).generate_token }

  # As três formas do aceite.
  let(:url_com_espaco) { 'https://loja.exemplo.com.br/produtos/tenis nike?utm_source=google&utm_medium=cpc' }
  let(:url_com_colchete) { 'https://loja.exemplo.com.br/produtos/[promo]/tenis?utm_source=google' }
  let(:url_que_nao_valida) { 'javascript:alert(document.cookie)' }

  def criar_conversa(referer_url)
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

  # Lê do BANCO, com uma consulta nova — não do objeto que o controller deixou em memória.
  def atributos_no_banco(display_id)
    Conversation.where(account_id: account.id, display_id: display_id).pick(:additional_attributes)
  end

  describe 'asserção (1) — URL com espaço não escapado preserva a origem' do
    it 'grava o referer escapado, e não nil' do
      display_id = criar_conversa(url_com_espaco)

      expect(atributos_no_banco(display_id)['referer']).to eq(
        'https://loja.exemplo.com.br/produtos/tenis%20nike?utm_source=google&utm_medium=cpc'
      )
    end
  end

  describe 'asserção (2) — URL com colchete cru preserva a origem' do
    it 'grava o referer escapado, e não nil' do
      display_id = criar_conversa(url_com_colchete)

      expect(atributos_no_banco(display_id)['referer']).to eq(
        'https://loja.exemplo.com.br/produtos/%5Bpromo%5D/tenis?utm_source=google'
      )
    end
  end

  describe 'asserção (3) — o que não valida vai para referer_raw, nunca nil silencioso' do
    it 'zera o referer mas preserva o valor cru' do
      display_id = criar_conversa(url_que_nao_valida)
      atributos = atributos_no_banco(display_id)

      expect(atributos['referer']).to be_nil
      expect(atributos['referer_raw']).to eq('javascript:alert(document.cookie)')
    end
  end

  describe 'asserção (4) — as 3 formas gravadas e relidas do banco na mesma corrida' do
    it 'devolve os 3 valores esperados' do
      ids = {
        espaco: criar_conversa(url_com_espaco),
        colchete: criar_conversa(url_com_colchete),
        invalida: criar_conversa(url_que_nao_valida)
      }

      lidos = ids.transform_values { |display_id| atributos_no_banco(display_id) }

      expect(lidos[:espaco]['referer']).to eq(
        'https://loja.exemplo.com.br/produtos/tenis%20nike?utm_source=google&utm_medium=cpc'
      )
      expect(lidos[:colchete]['referer']).to eq(
        'https://loja.exemplo.com.br/produtos/%5Bpromo%5D/tenis?utm_source=google'
      )
      expect(lidos[:invalida]['referer']).to be_nil
      expect(lidos[:invalida]['referer_raw']).to eq('javascript:alert(document.cookie)')

      # A regressão que este bloco corrige: nenhuma das três pode ser o `nil` silencioso de antes.
      preenchidos = lidos.values.count { |a| a['referer'].present? || a['referer_raw'].present? }
      expect(preenchidos).to eq(3)
    end
  end

  describe 'asserção (5a) — referer_raw não é servido ao widget' do
    it 'não aparece na resposta de criação nem na de leitura da conversa' do
      display_id = criar_conversa(url_que_nao_valida)
      corpo_da_criacao = response.body

      get '/api/v1/widget/conversations',
          headers: { 'X-Auth-Token' => token },
          params: { website_token: web_widget.website_token },
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['id']).to eq(display_id)

      expect(corpo_da_criacao).not_to include('referer_raw')
      expect(corpo_da_criacao).not_to include('javascript:alert')
      expect(response.body).not_to include('referer_raw')
      expect(response.body).not_to include('javascript:alert')
    end
  end
end
