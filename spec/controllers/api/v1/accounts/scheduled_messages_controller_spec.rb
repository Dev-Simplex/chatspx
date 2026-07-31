require 'rails_helper'

RSpec.describe 'Scheduled Messages API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:scheduled_at) { 2.hours.from_now }

  # O template do WhatsApp Oficial: fora da janela de 24h é a única coisa entregue,
  # então o agendamento tem que carregar isso até o envio.
  let(:template_params) do
    {
      name: 'lembrete_agendamento',
      namespace: 'ns',
      category: 'UTILITY',
      language: 'pt_BR',
      processed_params: { body: { '1' => 'Fulano', '2' => 'amanhã às 10h' } }
    }
  end

  describe 'POST /api/v1/accounts/{account.id}/scheduled_messages' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/scheduled_messages",
             params: { scheduled_message: { conversation_id: conversation.id, message: 'oi', scheduled_at: scheduled_at } },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'schedules a plain text message' do
        post "/api/v1/accounts/#{account.id}/scheduled_messages",
             params: { scheduled_message: { conversation_id: conversation.id, message: 'até amanhã', scheduled_at: scheduled_at } },
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:created)
        expect(ScheduledMessage.last.message).to eq('até amanhã')
        expect(ScheduledMessage.last.template_params).to be_blank
      end

      # Regressão: `template_params` não estava na lista de permitidos, então a
      # chave era descartada em silêncio — o serviço e o envio já sabiam usá-la,
      # mas ela nunca chegava lá, e o agendamento saía como texto puro.
      it 'persists template_params sent by the client' do
        post "/api/v1/accounts/#{account.id}/scheduled_messages",
             params: {
               scheduled_message: {
                 conversation_id: conversation.id,
                 message: 'Olá Fulano, seu atendimento está agendado para amanhã às 10h.',
                 scheduled_at: scheduled_at,
                 template_params: template_params
               }
             },
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:created)

        persisted = ScheduledMessage.last.template_params
        expect(persisted).to be_present
        expect(persisted['name']).to eq('lembrete_agendamento')
        expect(persisted['language']).to eq('pt_BR')
        expect(persisted.dig('processed_params', 'body', '1')).to eq('Fulano')
      end

      # Com conversation_id o backend usa a caixa da própria conversa; para agendar
      # em OUTRA caixa o cliente manda contact_id + inbox_id, e o backend resolve
      # (ou cria) a conversa daquele contato lá.
      it 'schedules on another inbox when given contact_id and inbox_id' do
        other_inbox = create(:inbox, account: account)

        post "/api/v1/accounts/#{account.id}/scheduled_messages",
             params: {
               scheduled_message: {
                 contact_id: contact.id,
                 inbox_id: other_inbox.id,
                 message: 'mensagem na outra caixa',
                 scheduled_at: scheduled_at
               }
             },
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:created)
        expect(ScheduledMessage.last.inbox_id).to eq(other_inbox.id)
        expect(ScheduledMessage.last.conversation.inbox_id).to eq(other_inbox.id)
      end
    end

    # A policy so pergunta "e agente/admin da conta?". Sem a guarda de caixa no
    # controller, um agente agendava por QUALQUER caixa — inclusive uma de que nao
    # e membro — e no caminho contact_id + inbox_id o backend ainda criava a
    # conversa la. Escrita futura, sem ninguem olhando.
    context 'when the agent is not a member of the target inbox' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:foreign_inbox) { create(:inbox, account: account) }

      it 'refuses to schedule' do
        expect do
          post "/api/v1/accounts/#{account.id}/scheduled_messages",
               params: {
                 scheduled_message: {
                   contact_id: contact.id,
                   inbox_id: foreign_inbox.id,
                   message: 'caixa que nao e minha',
                   scheduled_at: scheduled_at
                 }
               },
               headers: agent.create_new_auth_token,
               as: :json
        end.not_to change(ScheduledMessage, :count)

        expect(response).to have_http_status(:unauthorized)
      end

      it 'allows scheduling on an inbox the agent belongs to' do
        create(:inbox_member, user: agent, inbox: inbox)

        post "/api/v1/accounts/#{account.id}/scheduled_messages",
             params: {
               scheduled_message: {
                 conversation_id: conversation.id,
                 message: 'minha caixa',
                 scheduled_at: scheduled_at
               }
             },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:created)
      end
    end
  end
end
