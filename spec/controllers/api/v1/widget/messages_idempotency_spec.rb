# frozen_string_literal: true

require 'rails_helper'

# Mecanismo de aceite do bloco 2.15.
#
# ACEITE (§2.2): "Retry de rede com a mesma chave não duplica mensagem".
#
# O caso real: o visitante toca em enviar, a mensagem chega ao servidor, e a
# RESPOSTA se perde no caminho de volta (túnel, elevador, troca de antena). O
# widget não tem como saber que deu certo — ele reenvia. Sem chave, o agente vê
# a mesma frase duas vezes e o visitante parece nervoso.
#
# `echo_id` JÁ viajava do widget para o servidor (`base_controller.rb:94`), mas
# é `attr_accessor` no modelo (`message.rb:89`): virtual, some depois do
# broadcast, e não protege nada. Este bloco o persiste em `source_id` — coluna e
# índice que já existem — e passa a conferir antes de criar.
RSpec.describe 'Widget messages — idempotência de envio', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
  let(:conversation) { create(:conversation, contact: contact, inbox: web_widget.inbox, contact_inbox: contact_inbox) }
  let(:token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id }).generate_token
  end

  def enviar(conteudo, echo_id)
    post "/api/v1/widget/messages?website_token=#{web_widget.website_token}",
         headers: { 'X-Auth-Token' => token },
         params: { message: { content: conteudo, echo_id: echo_id, timestamp: Time.current.to_i } },
         as: :json
  end

  before { conversation }

  # Contar `conversation.messages` inteiro mediria tambem as automaticas que o
  # envio dispara (medido: um POST mexe em 3 linhas). O aceite e sobre NAO
  # DUPLICAR A MENSAGEM DO VISITANTE, entao e ela que se conta.
  def mensagens_com(conteudo)
    conversation.messages.where(content: conteudo, message_type: :incoming)
  end

  it 'o mesmo envio, repetido, cria UMA mensagem' do
    expect { enviar('bom dia', 'chave-1') }.to change { mensagens_com('bom dia').count }.by(1)

    expect { enviar('bom dia', 'chave-1') }.not_to(change { mensagens_com('bom dia').count })
    expect(response).to have_http_status(:success)
  end

  it 'a segunda resposta devolve a MESMA mensagem, não um erro' do
    enviar('bom dia', 'chave-1')
    primeiro_id = response.parsed_body['id']

    enviar('bom dia', 'chave-1')

    expect(response.parsed_body['id']).to eq(primeiro_id)
  end

  it 'chaves diferentes criam mensagens diferentes — o visitante pode repetir de propósito' do
    enviar('oi', 'chave-1')

    expect { enviar('oi', 'chave-2') }.to change { mensagens_com('oi').count }.by(1)
  end

  it 'sem chave nenhuma, o comportamento de hoje continua: cada envio é uma mensagem' do
    expect { enviar('oi', nil) }.to change { mensagens_com('oi').count }.by(1)
    expect { enviar('oi', nil) }.to change { mensagens_com('oi').count }.by(1)
  end

  it 'a chave fica gravada, e é por isso que o retry a encontra' do
    enviar('bom dia', 'chave-1')

    expect(mensagens_com('bom dia').last.source_id).to eq('chave-1')
  end

  it 'a chave de uma conversa não bloqueia outra' do
    outra = create(:conversation, contact: contact, inbox: web_widget.inbox, contact_inbox: contact_inbox)
    enviar('oi', 'chave-1')

    expect { outra.messages.create!(account: account, inbox: web_widget.inbox, message_type: :incoming, content: 'oi', source_id: 'chave-1') }
      .to change(outra.messages, :count).by(1)
  end
end
