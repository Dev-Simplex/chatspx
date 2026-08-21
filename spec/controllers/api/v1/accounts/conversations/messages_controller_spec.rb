require 'rails_helper'

RSpec.describe 'Conversation Messages API', type: :request do
  let!(:account) { create(:account) }

  describe 'POST /api/v1/accounts/{account.id}/conversations/<id>/messages' do
    let!(:inbox) { create(:inbox, account: account) }
    let!(:conversation) { create(:conversation, inbox: inbox, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user with access to conversation' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
      end

      it 'creates a new outgoing message' do
        params = { content: 'test-message', private: true }

        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(response).to conform_schema(200)
        expect(conversation.messages.count).to eq(1)
        expect(conversation.messages.first.content).to eq(params[:content])
      end

      it 'does not create the message' do
        params = { content: "#{'h' * 150 * 1000}a", private: true }

        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)

        json_response = response.parsed_body

        expect(json_response['error']).to eq('Validation failed: Content is too long (maximum is 150000 characters)')
      end

      it 'creates an outgoing text message with a specific bot sender' do
        agent_bot = create(:agent_bot)
        time_stamp = Time.now.utc.to_s
        params = { content: 'test-message', external_created_at: time_stamp, sender_type: 'AgentBot', sender_id: agent_bot.id }

        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        response_data = response.parsed_body
        expect(response_data['content_attributes']['external_created_at']).to eq time_stamp
        expect(conversation.messages.count).to eq(1)
        expect(conversation.messages.last.sender_id).to eq(agent_bot.id)
        expect(conversation.messages.last.content_type).to eq('text')
      end

      it 'creates a new outgoing message with attachment' do
        file = fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')
        params = { content: 'test-message', attachments: [file] }

        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: agent.create_new_auth_token

        expect(response).to have_http_status(:success)
        expect(conversation.messages.last.attachments.first.file.present?).to be(true)
        expect(conversation.messages.last.attachments.first.file_type).to eq('image')
      end

      # D1 (D-4): guard "só o assignee responde" atrás da flag reply_assignment_gate.
      context 'when the reply assignment gate is enabled' do
        let(:assignee) { create(:user, account: account, role: :agent) }
        let(:gate_url) do
          api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id)
        end

        before do
          create(:inbox_member, inbox: conversation.inbox, user: assignee)
          conversation.update!(assignee: assignee)
          account.update!(reply_assignment_gate: true)
        end

        it 'blocks a non-assignee reply with 422 assignment_required and assignee meta' do
          post gate_url, params: { content: 'oi' }, headers: agent.create_new_auth_token, as: :json

          expect(response).to have_http_status(:unprocessable_entity)
          json = response.parsed_body
          expect(json['error_code']).to eq('assignment_required')
          expect(json['meta']['current_assignee']['id']).to eq(assignee.id)
          expect(json['meta']['current_assignee']['type']).to eq('User')
          expect(conversation.reload.messages.where(message_type: :outgoing).count).to eq(0)
        end

        it 'allows the assignee to reply' do
          post gate_url, params: { content: 'oi' }, headers: assignee.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
        end

        it 'allows a non-assignee private note (bypass)' do
          post gate_url, params: { content: 'nota', private: true }, headers: agent.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
        end

        it 'allows a payload carrying source_id (external WAHA echo bypass)' do
          post gate_url, params: { content: 'echo', source_id: 'WAID-123' }, headers: agent.create_new_auth_token, as: :json

          expect(response).not_to have_http_status(:unprocessable_entity)
        end

        it 'does not gate an incoming message_type via API (bypass)' do
          # Agent-posted incoming 500s downstream regardless of the gate (pre-existing
          # fork behavior); here we only assert the gate itself did not block it (no 422).
          post gate_url, params: { content: 'in', message_type: 'incoming' }, headers: agent.create_new_auth_token, as: :json

          expect(response).not_to have_http_status(:unprocessable_entity)
        end

        context 'when the conversation is owned by an AI mirror' do
          let(:assistant) { create(:captain_assistant, account: account, name: 'Júlia') }

          before { conversation.update!(assignee: nil, assignee_agent_bot: assistant.mirror_agent_bot) }

          it 'reports the AI as current_assignee in the 422 meta' do
            post gate_url, params: { content: 'oi' }, headers: agent.create_new_auth_token, as: :json

            expect(response).to have_http_status(:unprocessable_entity)
            json = response.parsed_body
            expect(json['meta']['current_assignee']['type']).to eq('AgentBot')
            expect(json['meta']['current_assignee']['name']).to eq('Júlia')
          end
        end
      end

      context 'when the reply assignment gate is disabled (classic mode, default)' do
        let(:assignee) { create(:user, account: account, role: :agent) }

        before { conversation.update!(assignee: assignee) }

        it 'lets a non-assignee reply (gate inert)' do
          post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
               params: { content: 'oi' }, headers: agent.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
        end
      end

      context 'when api inbox' do
        let(:api_channel) { create(:channel_api, account: account) }
        let(:api_inbox) { create(:inbox, channel: api_channel, account: account) }
        let(:conversation) { create(:conversation, inbox: api_inbox, account: account) }

        it 'reopens the conversation with new incoming message' do
          create(:message, conversation: conversation, account: account)
          conversation.resolved!

          params = { content: 'test-message', private: false, message_type: 'incoming' }

          post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
               params: params,
               headers: agent.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:success)
          expect(conversation.reload.status).to eq('open')
          expect(Conversations::ActivityMessageJob)
            .to(have_been_enqueued.at_least(:once)
              .with(conversation, { account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity,
                                    content: 'System reopened the conversation due to a new incoming message.' }))
        end

        context 'when waha session is bound and content matches a WAHA echo' do
          before { api_inbox.update!(waha_session_name: 'simplexteste') }

          it 'suppresses the duplicate location echo created by the external WAHA app' do
            params = {
              content: "*📱 Enviado via API*\n\n📍 **Localização compartilhada**\n\n🔗 **Ver no mapa:** https://www.google.com/maps?q=-11.87,-55.52"
            }

            expect do
              post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
                   params: params,
                   headers: agent.create_new_auth_token,
                   as: :json
            end.not_to change(conversation.messages, :count)

            expect(response).to have_http_status(:success)
            expect(response.parsed_body['status']).to eq('suppressed')
          end

          it 'suppresses the duplicate contact echo created by the external WAHA app' do
            params = {
              content: "*📱 Enviado via API*\n\n👤 **Contato compartilhado**\n\nNome: Walisson\nTelefone: +55 66 9999-0000"
            }

            expect do
              post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
                   params: params,
                   headers: agent.create_new_auth_token,
                   as: :json
            end.not_to change(conversation.messages, :count)

            expect(response).to have_http_status(:success)
            expect(response.parsed_body['status']).to eq('suppressed')
          end

          it 'still suppresses the legacy "edited on WhatsApp" echo' do
            params = {
              content: "*📱 Enviado via API*\n\n✏️ Editado no WhatsApp"
            }

            expect do
              post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
                   params: params,
                   headers: agent.create_new_auth_token,
                   as: :json
            end.not_to change(conversation.messages, :count)

            expect(response).to have_http_status(:success)
            expect(response.parsed_body['status']).to eq('suppressed')
          end

          it 'does not suppress regular outgoing text that mentions the API marker only' do
            params = { content: 'Olá, esta é uma mensagem normal Enviado via API que o agente digitou' }

            expect do
              post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
                   params: params,
                   headers: agent.create_new_auth_token,
                   as: :json
            end.to change(conversation.messages, :count).by(1)

            expect(response).to have_http_status(:success)
          end

          it 'suppresses full waha error message (toast + insert error)' do
            params = {
              content: <<~TXT
                ⚠️ Não foi possível receber uma mensagem do WhatsApp
                ❌ Não há mais tentativas restantes. Por favor, tente novamente mais tarde.
                Tentativa: 3 / 3
                Detalhes: whatsapp | message.any => 736643

                error: insert into "app_chatwoot_chatwoot_messages" ("app_pk", "conversation_id", "message_id", "timestamp") values ($1, $2, $3, $4) - invalid input syntax for type timestamp with time zone: "0NaN-NaN-NaNTNaN:NaN:NaN.NaN+NaN:NaN"
              TXT
            }

            expect do
              post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
                   params: params,
                   headers: agent.create_new_auth_token,
                   as: :json
            end.not_to change(conversation.messages, :count)

            expect(response).to have_http_status(:success)
            expect(response.parsed_body['status']).to eq('suppressed')
            expect(response.parsed_body['reason']).to eq('waha_error_message')
          end

          it 'suppresses waha error toast even without insert error (just toast + retries)' do
            params = {
              content: "⚠️ Não foi possível receber uma mensagem do WhatsApp\n❌ Não há mais tentativas restantes."
            }

            expect do
              post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
                   params: params,
                   headers: agent.create_new_auth_token,
                   as: :json
            end.not_to change(conversation.messages, :count)

            expect(response).to have_http_status(:success)
            expect(response.parsed_body['status']).to eq('suppressed')
            expect(response.parsed_body['reason']).to eq('waha_error_message')
          end

          it 'does not suppress legitimate text that contains only one waha error marker' do
            params = { content: 'Não foi possível terminar agora, te chamo mais tarde' }

            expect do
              post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
                   params: params,
                   headers: agent.create_new_auth_token,
                   as: :json
            end.to change(conversation.messages, :count).by(1)

            expect(response).to have_http_status(:success)
          end

          it 'suppresses error message combining "Tentativa: 3 / 3" and "app_chatwoot_chatwoot_messages"' do
            params = {
              content: <<~TXT
                Tentativa: 3 / 3
                ChatWoot replicou: insert into "app_chatwoot_chatwoot_messages" failed with timestamp NaN
              TXT
            }

            expect do
              post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
                   params: params,
                   headers: agent.create_new_auth_token,
                   as: :json
            end.not_to change(conversation.messages, :count)

            expect(response).to have_http_status(:success)
            expect(response.parsed_body['status']).to eq('suppressed')
            expect(response.parsed_body['reason']).to eq('waha_error_message')
          end
        end
      end
    end

    context 'when it is an authenticated agent bot' do
      let!(:agent_bot) { create(:agent_bot) }

      it 'creates a new outgoing message' do
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        params = { content: 'test-message' }

        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: { api_access_token: agent_bot.access_token.token },
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.messages.count).to eq(1)
        expect(conversation.messages.first.content).to eq(params[:content])
      end

      it 'creates a new outgoing input select message' do
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        select_item1 = build(:bot_message_select)
        select_item2 = build(:bot_message_select)
        params = { content_type: 'input_select', content_attributes: { items: [select_item1, select_item2] } }

        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: { api_access_token: agent_bot.access_token.token },
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.messages.count).to eq(1)
        expect(conversation.messages.first.content_type).to eq(params[:content_type])
        expect(conversation.messages.first.content).to be_nil
      end

      it 'creates a new outgoing cards message' do
        create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
        card = build(:bot_message_card)
        params = { content_type: 'cards', content_attributes: { items: [card] } }

        post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
             params: params,
             headers: { api_access_token: agent_bot.access_token.token },
             as: :json

        expect(response).to have_http_status(:success)
        expect(conversation.messages.count).to eq(1)
        expect(conversation.messages.first.content_type).to eq(params[:content_type])
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/conversations/:id/messages/share_location' do
    let!(:share_inbox) { create(:inbox, account: account) }
    let!(:share_conversation) { create(:conversation, inbox: share_inbox, account: account) }
    let(:share_agent) { create(:user, account: account, role: :agent) }

    before { create(:inbox_member, inbox: share_conversation.inbox, user: share_agent) }

    context 'when payload has coordinates and address' do
      let(:share_address) { 'Av. Brasil, 1000 — Sinop, MT' }
      let(:share_params) { { latitude: -11.87, longitude: -55.52, address: share_address } }

      def post_share_location
        post "/api/v1/accounts/#{account.id}/conversations/#{share_conversation.display_id}/messages/share_location",
             params: share_params, headers: share_agent.create_new_auth_token, as: :json
      end

      it 'creates an outgoing message with empty content and address preserved in additional_attributes' do
        expect { post_share_location }.to change(share_conversation.messages, :count).by(1)

        message = share_conversation.messages.last
        expect(response).to have_http_status(:success)
        expect(message.content).to eq('')
        expect(message.message_type).to eq('outgoing')
        expect(message.additional_attributes.dig('location', 'address')).to eq(share_address)
      end

      it 'creates a location attachment carrying coordinates and the full address as fallback_title' do
        post_share_location

        attachment = share_conversation.messages.last.attachments.first
        expect(attachment).to be_present
        expect(attachment.file_type).to eq('location')
        expect(attachment.coordinates_lat).to eq(-11.87)
        expect(attachment.coordinates_long).to eq(-55.52)
        expect(attachment.fallback_title).to eq(share_address)
      end

      it 'creates the message even when address is blank (coordinates-only)' do
        params = { latitude: -11.87, longitude: -55.52 }

        expect do
          post "/api/v1/accounts/#{account.id}/conversations/#{share_conversation.display_id}/messages/share_location",
               params: params,
               headers: share_agent.create_new_auth_token,
               as: :json
        end.to change(share_conversation.messages, :count).by(1)

        expect(response).to have_http_status(:success)
        message = share_conversation.messages.last
        expect(message.content).to eq('')
        expect(message.attachments.first.fallback_title).to be_nil
      end
    end

    context 'when coordinates are missing' do
      it 'returns an error and does not create a message' do
        params = { latitude: 0, longitude: 0, address: 'nowhere' }

        expect do
          post "/api/v1/accounts/#{account.id}/conversations/#{share_conversation.display_id}/messages/share_location",
               params: params,
               headers: share_agent.create_new_auth_token,
               as: :json
        end.not_to change(share_conversation.messages, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/conversations/:id/messages' do
    let(:conversation) { create(:conversation, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user with access to conversation' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
      end

      it 'shows the conversation' do
        get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response).to conform_schema(200)
        expect(JSON.parse(response.body, symbolize_names: true)[:meta][:contact][:id]).to eq(conversation.contact_id)
      end

      # PR 0.1 — hardening: garante que os campos `starred`, `forwarded`,
      # `forwarded_from_message_id` e `additional_attributes` chegam ao
      # cliente REST. Eles já eram enviados via ActionCable
      # (Message#push_event_data), mas o jbuilder não os expunha — o que
      # quebrava o cold-start de clientes mobile que dependem do GET.
      context 'when serializing message payload (PR 0.1 hardening)' do
        let!(:plain_message) do
          create(:message, account: account, inbox: conversation.inbox, conversation: conversation)
        end

        let!(:starred_forwarded_message) do
          source = create(:message, account: account, inbox: conversation.inbox, conversation: conversation)
          create(
            :message,
            account: account,
            inbox: conversation.inbox,
            conversation: conversation,
            starred: true,
            forwarded: true,
            forwarded_from_message_id: source.id,
            additional_attributes: { 'location' => { 'address' => 'Av. Brasil, 1000' } }
          )
        end

        def fetch_message(id)
          get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
              headers: agent.create_new_auth_token,
              as: :json
          response.parsed_body['payload'].find { |m| m['id'] == id }
        end

        it 'serializes defaults (starred=false, forwarded=false, forwarded_from=nil) on a plain message' do
          payload = fetch_message(plain_message.id)

          expect(payload).to include(
            'starred' => false,
            'forwarded' => false,
            'forwarded_from_message_id' => nil
          )
          expect(payload).to have_key('additional_attributes')
        end

        it 'serializes truthy starred/forwarded plus forwarded_from_message_id and additional_attributes' do
          payload = fetch_message(starred_forwarded_message.id)

          expect(payload['starred']).to be(true)
          expect(payload['forwarded']).to be(true)
          expect(payload['forwarded_from_message_id']).to eq(starred_forwarded_message.forwarded_from_message_id)
          expect(payload['additional_attributes']).to eq(
            'location' => { 'address' => 'Av. Brasil, 1000' }
          )
        end
      end

      context 'with cursor pagination params' do
        before do
          create_list(
            :message,
            65,
            account: account,
            inbox: conversation.inbox,
            conversation: conversation
          )
        end

        it 'respects custom limit and returns has_more' do
          get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
              params: { before: conversation.messages.maximum(:id) + 1, limit: 40 },
              headers: agent.create_new_auth_token,
              as: :json

          expect(response).to have_http_status(:success)
          body = response.parsed_body
          payload = body['payload']
          ids = payload.pluck('id')

          expect(payload.length).to eq(40)
          expect(ids).to eq(ids.sort)
          expect(body.dig('meta', 'has_more')).to be(true)
        end

        it 'caps limit above 100 to protect the endpoint' do
          create_list(
            :message,
            80,
            account: account,
            inbox: conversation.inbox,
            conversation: conversation
          )

          get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
              params: { before: conversation.messages.maximum(:id) + 1, limit: 250 },
              headers: agent.create_new_auth_token,
              as: :json

          expect(response).to have_http_status(:success)
          expect(response.parsed_body['payload'].length).to eq(100)
        end

        it 'supports include_meta=false with lightweight meta payload' do
          get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
              params: { before: conversation.messages.maximum(:id) + 1, include_meta: false, limit: 40 },
              headers: agent.create_new_auth_token,
              as: :json

          expect(response).to have_http_status(:success)
          meta = response.parsed_body['meta']

          expect(meta).to include('has_more')
          expect(meta).not_to have_key('contact')
          expect(meta).not_to have_key('labels')
          expect(meta).not_to have_key('additional_attributes')
        end

        it 'returns has_more=false on the last page' do
          oldest_id = conversation.messages.minimum(:id)

          get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
              params: { before: oldest_id + 1, include_meta: false, limit: 40 },
              headers: agent.create_new_auth_token,
              as: :json

          expect(response).to have_http_status(:success)
          expect(response.parsed_body.dig('meta', 'has_more')).to be(false)
        end
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/conversations/:conversation_id/messages/:id' do
    let(:message) { create(:message, account: account, content_attributes: { bcc_emails: ['hello@chatwoot.com'] }) }
    let(:conversation) { message.conversation }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user with access to conversation' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
      end

      it 'deletes the message and preserves the original content for the history card' do
        original_content = message.content

        delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        message.reload
        # `I18n.t` sem `locale:` resolve no idioma do PROCESSO (:en no rails_helper); a
        # resposta sai no idioma da CONTA (pt-BR por padrao, decisao nossa). Ver 4cab065b87.
        expect(message.content).to eq I18n.t('conversations.messages.deleted', locale: account.locale)
        expect(message.deleted).to be true
        expect(message.content_attributes['previous_content']).to eq original_content
        expect(message.content_attributes['deleted_at']).to be_present
        expect(message.content_attributes['deleted_by']).to include('id' => agent.id, 'name' => agent.name)
        # Unrelated attributes are merged/preserved (no longer zeroed out)
        expect(message.content_attributes['bcc_emails']).to eq ['hello@chatwoot.com']
      end

      it 'surfaces a friendly error when the WAHA call times out' do
        service = instance_double(Messages::DeleteContentService)
        allow(Messages::DeleteContentService).to receive(:new).and_return(service)
        allow(service).to receive(:perform).and_raise(Rack::Timeout::RequestTimeoutException.new({}))

        delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq I18n.t('errors.messages.update.timeout')
      end

      it 'returns 422 for NPS/CSAT messages' do
        nps_message = create(:message, message_type: :outgoing, content: 'rate us',
                                       content_type: 'input_csat', conversation: conversation)

        delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{nps_message.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(nps_message.reload.deleted).to be_falsey
      end

      it 'deletes interactive messages' do
        interactive_message = create(
          :message, message_type: :outgoing, content: 'test', content_type: 'input_select',
                    content_attributes: { 'items' => [{ 'title' => 'test', 'value' => 'test' }] },
                    conversation: conversation
        )

        delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{interactive_message.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(interactive_message.reload.deleted).to be true
      end
    end

    context 'when the message id is invalid' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: conversation.inbox, user: agent)
      end

      it 'returns not found error' do
        delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/99999",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/conversations/:conversation_id/messages/:id/retry' do
    let(:message) { create(:message, account: account, status: :failed, content_attributes: { external_error: 'error' }) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/conversations/#{message.conversation.display_id}/messages/#{message.id}/retry"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user with access to conversation' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: message.conversation.inbox, user: agent)
      end

      it 'retries the message' do
        post "/api/v1/accounts/#{account.id}/conversations/#{message.conversation.display_id}/messages/#{message.id}/retry",
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(message.reload.status).to eq('sent')
        expect(message.reload.content_attributes['external_error']).to be_nil
      end
    end

    context 'when the message id is invalid' do
      let(:agent) { create(:user, account: account, role: :agent) }

      before do
        create(:inbox_member, inbox: message.conversation.inbox, user: agent)
      end

      it 'returns not found error' do
        post "/api/v1/accounts/#{account.id}/conversations/#{message.conversation.display_id}/messages/99999/retry",
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when retrying a WAHA interactive (input_select) message' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:waha_channel) { create(:channel_api, account: account) }
      let(:waha_inbox) do
        ib = waha_channel.inbox
        ib.update!(waha_session_name: 'default')
        ib
      end
      let(:waha_conversation) { create(:conversation, account: account, inbox: waha_inbox) }
      let(:message) do
        create(:message, account: account, conversation: waha_conversation, inbox: waha_inbox,
                         message_type: :outgoing, status: :failed,
                         content: 'Como ajudar?', content_type: :input_select,
                         content_attributes: { items: [{ 'title' => 'Sim', 'value' => 'sim' }], external_error: 'boom' })
      end

      before do
        create(:inbox_member, inbox: waha_inbox, user: agent)
        special = instance_double(Waha::OutboundSpecialMessageService, perform: true)
        allow(Waha::OutboundSpecialMessageService).to receive(:new).and_return(special)
      end

      it 'preserves items, clears the error and re-dispatches via WAHA without 500' do
        post "/api/v1/accounts/#{account.id}/conversations/#{waha_conversation.display_id}/messages/#{message.id}/retry",
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(message.reload.content_attributes['items']).to eq([{ 'title' => 'Sim', 'value' => 'sim' }])
        expect(message.reload.content_attributes['external_error']).to be_nil
        expect(Waha::OutboundSpecialMessageService).to have_received(:new)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/conversations/:conversation_id/messages/:id' do
    let(:api_channel) { create(:channel_api, account: account) }
    let(:api_inbox) { create(:inbox, channel: api_channel, account: account) }
    let(:agent) { create(:user, account: account, role: :agent) }
    let!(:conversation) { create(:conversation, inbox: api_inbox, account: account) }
    let!(:message) { create(:message, conversation: conversation, account: account, status: :sent) }

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        patch api_v1_account_conversation_message_url(account_id: account.id, conversation_id: conversation.display_id, id: message.id)
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated agent' do
      context 'when agent has non-API inbox' do
        let(:inbox) { create(:inbox, account: account) }
        let(:agent) { create(:user, account: account, role: :agent) }
        let!(:conversation) { create(:conversation, inbox: inbox, account: account) }

        before { create(:inbox_member, inbox: inbox, user: agent) }

        it 'returns forbidden' do
          patch api_v1_account_conversation_message_url(
            account_id: account.id,
            conversation_id: conversation.display_id,
            id: message.id
          ), params: { status: 'failed', external_error: 'err' }, headers: agent.create_new_auth_token, as: :json
          expect(response).to have_http_status(:forbidden)
        end
      end

      context 'when agent has API inbox' do
        before { create(:inbox_member, inbox: api_inbox, user: agent) }

        it 'uses StatusUpdateService to perform status update' do
          service = instance_double(Messages::StatusUpdateService)
          expect(Messages::StatusUpdateService).to receive(:new)
            .with(message, 'failed', 'err123')
            .and_return(service)
          expect(service).to receive(:perform)
          patch api_v1_account_conversation_message_url(
            account_id: account.id,
            conversation_id: conversation.display_id,
            id: message.id
          ), params: { status: 'failed', external_error: 'err123' }, headers: agent.create_new_auth_token, as: :json
        end

        it 'updates status to failed with external_error' do
          patch api_v1_account_conversation_message_url(
            account_id: account.id,
            conversation_id: conversation.display_id,
            id: message.id
          ), params: { status: 'failed', external_error: 'err123' }, headers: agent.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
          expect(message.reload.status).to eq('failed')
          expect(message.reload.external_error).to eq('err123')
        end
      end
    end
  end
end
