# frozen_string_literal: true

require 'rails_helper'

# 4.18 — A JUNTA, ATRAVESSADA COM O CORPO REAL DO CLIENTE.
#
# `spec/controllers/api/v1/widget/partial_leads_spec.rb` percorre o aceite inteiro e mesmo
# assim nao viu o defeito: o helper `responde` monta `website_token` A MAO. Do outro lado, o
# spec de tela dubla o modulo inteiro (`vi.mock('widget/api/partialLead')`) e afirma sobre os
# ARGUMENTOS da chamada. Cada lado provou o seu lado, o corpo que sai do navegador nunca
# encostou no Rails, e em producao toda gravacao morreria em 404 — engolido pelo `catch` do
# modulo, que e "melhor esforco" de proposito. Sem uma linha gravada nao ha lead incompleto,
# nao ha materializacao e nao ha denominador: o bloco inteiro seria decorativo.
#
# ESTE spec nao monta payload. Ele LE a requisicao que o cliente de verdade poe na rede,
# capturada de `widget/api/partialLead.js` rodando sobre o axios de verdade em
# `app/javascript/widget/api/specs/partialLeadJunta.spec.js`, e a envia ao Rails.
#
# So o VALOR do token e substituido, porque ele nasce da conta que este spec acabou de criar e
# o navegador nao teria como adivinha-lo. A CHAVE e o lugar dela vem da fixture.
RSpec.describe 'A junta do lead incompleto (4.18)', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:contact) { create(:contact, account: account, email: nil, phone_number: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }

  # O `X-Auth-Token` NAO vem da fixture de proposito: quem o instala e o boot do widget
  # (`setHeader`), nao o modulo do bloco. O que a fixture guarda e o contrato DESTE modulo.
  let(:session_header) do
    token = Widget::TokenService.new(
      payload: { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id }
    ).generate_token
    { 'X-Auth-Token' => token }
  end

  let(:fixture) { JSON.parse(Rails.root.join('spec/fixtures/widget_partial_lead_wire.json').read) }
  let(:sentinela) { fixture.fetch('sentinel_website_token') }
  let(:rascunho) { fixture.fetch('requests').first }

  after { Current.reset }

  def enable_capture!
    account.update!(internal_attributes: account.internal_attributes.merge('partial_lead_capture_enabled' => true))
  end

  # Troca o sentinela pelo token do canal criado aqui, em qualquer profundidade e tanto na
  # query quanto no corpo — a fixture e quem decide onde o token mora, nao este spec.
  def com_token_real(valor)
    case valor
    when Hash then valor.transform_values { |v| com_token_real(v) }
    when Array then valor.map { |v| com_token_real(v) }
    when sentinela then web_widget.website_token
    else valor
    end
  end

  def envia(requisicao)
    query = com_token_real(requisicao['params'])
    url = requisicao['url']
    url = "#{url}?#{query.to_query}" if query.present?

    post url, params: com_token_real(requisicao['body']), headers: session_header, as: :json
  end

  describe 'o corpo que o navegador poe na rede chega ao servidor' do
    before { enable_capture! }

    it 'grava a resposta parcial — e e a UNICA prova de que o lead incompleto existe' do
      expect { envia(rascunho) }.to change(WidgetPartialLead, :count).by(1)

      expect(response).to have_http_status(:ok)
    end

    it 'grava as RESPOSTAS e a ETAPA que o cliente mandou, nao as que este spec escolheu' do
      envia(rascunho)

      lead = WidgetPartialLead.last
      corpo = rascunho['body']
      expect(lead.answers).to eq(corpo['answers'])
      expect(lead.step_reached).to eq(corpo['step'])
      expect(lead.step_key).to eq(corpo['step_key'])
      expect(lead.session_id).to eq(contact_inbox.source_id)
    end

    it 'a sessao vem do TOKEN, nunca do corpo — o cliente nao escreve na sessao de outro visitante' do
      envia(rascunho)

      # A fixture nao carrega `session_id`; se um dia carregar, esta assercao continua exigindo
      # que o servidor use o do token. E o que impede um cliente adulterado de sobrescrever o
      # rascunho de outra pessoa.
      expect(rascunho['body']).not_to have_key('session_id')
      expect(WidgetPartialLead.last.session_id).to eq(contact_inbox.source_id)
    end
  end

  # ── A CONDICAO RUIM, FORCADA ──────────────────────────────────────────────────────────────
  #
  # Sem esta parte os exemplos acima seriam so «o corpo de hoje funciona». Ela prova que este
  # spec MEDE a junta: e o mesmo corpo, com uma unica peca removida, e ele tem de cair.
  describe 'a prova de que este spec mede a junta, e nao o corpo de hoje' do
    before { enable_capture! }

    it 'o MESMO corpo sem o `website_token` morre em 404 e nao grava nada' do
      sem_token = rascunho.deep_dup
      sem_token['params'].delete('website_token')
      sem_token['body'].delete('website_token')

      expect { envia(sem_token) }.not_to change(WidgetPartialLead, :count)
      expect(response).to have_http_status(:not_found)
    end

    it 'a fixture realmente carrega o sentinela — senao o 404 acima passaria por vacuo' do
      # Se o cliente parasse de mandar o token, a fixture perderia o sentinela, a substituicao
      # nao teria o que trocar e o exemplo negativo acima ficaria verde sem medir nada.
      expect(fixture['requests']).to be_present
      expect(fixture['requests']).to all(
        satisfy { |r| r['params'].to_json.include?(sentinela) || r['body'].to_json.include?(sentinela) }
      )
    end
  end

  describe 'o que o corpo real NAO faz' do
    it 'com a captura desligada devolve 200 e nao grava — o widget nao conhece a config do cliente' do
      expect { envia(rascunho) }.not_to change(WidgetPartialLead, :count)
      expect(response).to have_http_status(:ok)
    end

    it 'nao cria conversa: e por isso que o lead incompleto nao dispara automacao nem webhook' do
      enable_capture!

      expect { envia(rascunho) }.not_to change(Conversation, :count)
    end
  end
end
