# frozen_string_literal: true

require 'rails_helper'

# Bloco 2.15 — a TERCEIRA porta.
#
# ACEITE (§2.2): "Retry de rede com a mesma chave não duplica mensagem".
#
# `messages_idempotency_spec.rb` já cobre o POST de mensagem. Mas o pré-chat não
# passa por lá: ele bate em `POST /api/v1/widget/conversations`, que cria a
# CONVERSA e a primeira mensagem no mesmo request. Esse endpoint já permitia
# `echo_id` (`conversations_controller.rb:141`) e já o gravaria em `source_id`
# (`base_controller.rb#message_params`) — só que o widget nunca o mandava, e o
# controlador nunca o conferia. Um reenvio abria uma conversa NOVA com a mesma
# primeira frase: o visitante virava dois atendimentos.
RSpec.describe 'Widget pré-chat — idempotência de criação', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:contact) { create(:contact, account: account, email: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
  let(:token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id }).generate_token
  end

  def enviar_prechat(conteudo, echo_id)
    post '/api/v1/widget/conversations',
         headers: { 'X-Auth-Token' => token },
         params: {
           website_token: web_widget.website_token,
           contact: { name: 'Maria', email: 'maria@exemplo.com' },
           message: { content: conteudo, echo_id: echo_id }
         },
         as: :json
  end

  before { contact_inbox }

  def conversas
    contact_inbox.reload.conversations
  end

  def mensagens_com(conteudo)
    Message.where(content: conteudo, message_type: :incoming)
  end

  it 'o mesmo pré-chat, reenviado, cria UMA conversa' do
    expect { enviar_prechat('quero um orçamento', 'chave-pc-1') }.to change(conversas, :count).by(1)

    expect { enviar_prechat('quero um orçamento', 'chave-pc-1') }.not_to(change(conversas, :count))
    expect(response).to have_http_status(:success)
  end

  it 'o mesmo pré-chat, reenviado, cria UMA mensagem' do
    enviar_prechat('quero um orçamento', 'chave-pc-1')

    expect { enviar_prechat('quero um orçamento', 'chave-pc-1') }.not_to(change { mensagens_com('quero um orçamento').count })
  end

  it 'a segunda resposta devolve a MESMA conversa, não uma nova' do
    enviar_prechat('quero um orçamento', 'chave-pc-1')
    primeiro_id = response.parsed_body['id']

    enviar_prechat('quero um orçamento', 'chave-pc-1')

    expect(response.parsed_body['id']).to eq(primeiro_id)
  end

  # A trava contra corrigir demais: o visitante que RESOLVE a conversa e abre
  # outra manda uma chave nova, e essa conversa tem de nascer.
  it 'chaves diferentes criam conversas diferentes' do
    enviar_prechat('oi', 'chave-pc-1')

    expect { enviar_prechat('oi', 'chave-pc-2') }.to change(conversas, :count).by(1)
  end

  it 'sem chave nenhuma o comportamento de hoje continua: cada envio é uma conversa' do
    expect { enviar_prechat('oi', nil) }.to change(conversas, :count).by(1)
    expect { enviar_prechat('oi', nil) }.to change(conversas, :count).by(1)
  end

  it 'a chave fica gravada na primeira mensagem, e é por isso que o reenvio a encontra' do
    enviar_prechat('quero um orçamento', 'chave-pc-1')

    expect(mensagens_com('quero um orçamento').last.source_id).to eq('chave-pc-1')
  end

  # Escopo: a chave de um visitante não pode devolver a conversa de outro.
  it 'a chave de uma sessão não alcança a conversa de outra' do
    enviar_prechat('oi', 'chave-pc-1')

    outra_sessao = create(:contact_inbox, contact: create(:contact, account: account), inbox: web_widget.inbox)
    outro_token = Widget::TokenService.new(
      payload: { source_id: outra_sessao.source_id, inbox_id: web_widget.inbox.id }
    ).generate_token

    expect do
      post '/api/v1/widget/conversations',
           headers: { 'X-Auth-Token' => outro_token },
           params: {
             website_token: web_widget.website_token,
             contact: { name: 'Joao' },
             message: { content: 'oi', echo_id: 'chave-pc-1' }
           },
           as: :json
    end.to change { outra_sessao.reload.conversations.count }.by(1)
  end
end
