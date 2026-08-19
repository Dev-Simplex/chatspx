require 'rails_helper'

# Bloco 5.20 — a mensagem proativa do backend do cliente em UMA chamada.
#
# Hoje sao duas ou tres (ver o relatorio da trilha): achar o contato, achar/criar a conversa e —
# quando o chamador nao usa o `message` embutido — mandar a mensagem. A reducao que importa nao e de
# latencia, e de SUPERFICIE: com uma chamada, quem dispara nao precisa saber o que e contact_inbox,
# source_id nem display_id, e nao ha estado intermediario para vazar quando a segunda chamada falha.
RSpec.describe 'Api::V1::Accounts::ProactiveMessages', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }
  let(:contact) { create(:contact, account: account, email: 'maria@exemplo.com.br', identifier: 'cliente-42') }
  let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, hmac_verified: true) }

  def dispatch_proactive(params)
    post "/api/v1/accounts/#{account.id}/proactive_messages",
         params: { inbox_id: inbox.id, content: 'Seu orçamento está pronto' }.merge(params),
         headers: admin.create_new_auth_token,
         as: :json
  end

  describe 'uma chamada resolve contato, conversa e mensagem' do
    it 'cria a conversa e a mensagem de saída endereçando por e-mail' do
      expect { dispatch_proactive(email: 'maria@exemplo.com.br') }
        .to change(Conversation, :count).by(1)
        .and change(Message, :count).by(1)

      expect(response).to have_http_status(:success)
      message = Message.last
      expect(message.content).to eq('Seu orçamento está pronto')
      expect(message.message_type).to eq('outgoing')
      expect(message.conversation.contact_id).to eq(contact.id)
      expect(message.conversation.inbox_id).to eq(inbox.id)
    end

    it 'endereça por identifier e por phone_number também' do
      dispatch_proactive(identifier: 'cliente-42')
      expect(response).to have_http_status(:success)

      contact.update!(phone_number: '+5511999999999')
      dispatch_proactive(phone_number: '+5511999999999')
      expect(response).to have_http_status(:success)
      expect(Message.count).to eq(2)
    end

    it 'devolve o que o chamador precisa para continuar a conversa' do
      dispatch_proactive(email: 'maria@exemplo.com.br')

      body = response.parsed_body
      expect(body['conversation_id']).to eq(Conversation.last.display_id)
      expect(body['message_id']).to eq(Message.last.id)
      expect(body['contact_id']).to eq(contact.id)
    end

    # O ACEITE do bloco: o visitante recebe no widget aberto, em tempo real. O caminho e o
    # ActionCable que o `message.created` ja dispara — e a prova e o broadcast sair endereçado
    # ao pubsub_token DAQUELE contato, nao um broadcast qualquer.
    it 'transmite a mensagem ao visitante pelo canal em tempo real' do
      expect { dispatch_proactive(email: 'maria@exemplo.com.br') }
        .to have_enqueued_job(ActionCableBroadcastJob)
        .with(array_including(contact_inbox.pubsub_token), 'message.created', anything)
    end
  end

  describe 'a fila do atendimento nao infla sozinha (T-I6.2)' do
    it 'por padrão a conversa nasce fora da fila, esperando a resposta' do
      dispatch_proactive(email: 'maria@exemplo.com.br')

      conversation = Conversation.last
      expect(conversation.status).to eq('snoozed')
      expect(conversation.snoozed_until).to be_nil
    end

    # A prova de que "fora da fila" nao virou "perdida": o mecanismo de reabertura e o do proprio
    # produto (message.rb:462), e ele reage a resposta do contato.
    it 'a conversa entra na fila assim que o contato responde' do
      dispatch_proactive(email: 'maria@exemplo.com.br')
      conversation = Conversation.last

      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :incoming, sender: contact, content: 'Pode mandar')

      expect(conversation.reload.status).to eq('open')
    end

    it 'com create_conversation_without_contact_reply a conversa ja nasce na fila' do
      dispatch_proactive(email: 'maria@exemplo.com.br', create_conversation_without_contact_reply: true)

      expect(Conversation.last.status).to eq('open')
    end

    it 'nao mexe no status de uma conversa que ja existia' do
      existing = create(:conversation, account: account, inbox: inbox, contact: contact,
                                       contact_inbox: contact_inbox, status: :open)

      expect { dispatch_proactive(email: 'maria@exemplo.com.br') }.not_to change(Conversation, :count)
      expect(existing.reload.status).to eq('open')
      expect(existing.messages.last.content).to eq('Seu orçamento está pronto')
    end
  end

  describe 'mandar para o meu cliente, nao para quem digitou o e-mail dele (T-I6.3)' do
    # A MESMA sessao do resto do arquivo, so que sem assinatura conferida — e a diferenca entre
    # "meu cliente" e "quem digitou o e-mail dele".
    before { contact_inbox.update!(hmac_verified: false) }

    it 'recusa o disparo para contato nao verificado, dizendo o motivo' do
      expect { dispatch_proactive(email: 'maria@exemplo.com.br') }.not_to change(Message, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('verificad')
    end

    it 'dispara quando o chamador declara explicitamente que aceita nao verificado' do
      dispatch_proactive(email: 'maria@exemplo.com.br', allow_unverified_contact: true)

      expect(response).to have_http_status(:success)
      expect(Message.last.content).to eq('Seu orçamento está pronto')
    end
  end

  describe 'o que a requisicao recusa antes de criar qualquer coisa' do
    it 'recusa destinatario ausente' do
      dispatch_proactive({})

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('identifier')
    end

    it 'recusa conteudo em branco' do
      post "/api/v1/accounts/#{account.id}/proactive_messages",
           params: { inbox_id: inbox.id, email: 'maria@exemplo.com.br', content: '  ' },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'nao acha contato por correspondencia parcial — disparo nao e busca' do
      dispatch_proactive(email: 'maria@exemplo')

      expect(response).to have_http_status(:not_found)
      expect(Message.count).to eq(0)
    end

    it 'recusa quando o contato existe mas nunca esteve nesta inbox' do
      outro = create(:contact, account: account, email: 'sem-sessao@exemplo.com.br')
      expect(outro.contact_inboxes).to be_empty

      dispatch_proactive(email: 'sem-sessao@exemplo.com.br')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to be_present
    end

    it 'recusa inbox de outra conta' do
      outra_conta = create(:account)
      outra_inbox = create(:inbox, account: outra_conta)

      post "/api/v1/accounts/#{account.id}/proactive_messages",
           params: { inbox_id: outra_inbox.id, email: 'maria@exemplo.com.br', content: 'oi' },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'exige autenticacao' do
      post "/api/v1/accounts/#{account.id}/proactive_messages",
           params: { inbox_id: inbox.id, email: 'maria@exemplo.com.br', content: 'oi' }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'recusa um agente sem acesso a inbox' do
      agente = create(:user, account: account, role: :agent)

      post "/api/v1/accounts/#{account.id}/proactive_messages",
           params: { inbox_id: inbox.id, email: 'maria@exemplo.com.br', content: 'oi' },
           headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
