require 'rails_helper'

# Entrada assinada do Captador (22 §1.4): contato, conversa e 1ª mensagem em nome do usuário real,
# pelas mesmas travas do fork.
RSpec.describe 'Spx::Captador::Leads', type: :request do
  include CaptadorSigningHelpers

  let(:path) { '/spx/captador/v1/leads' }
  let(:account) { create(:account) }
  let(:templates) do
    [
      { 'name' => 'prospeccao_b2b_v1', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
        'components' => [{ 'type' => 'BODY', 'text' => 'Olá! Vi que a {{1}} atua em {{2}}.' }] },
      { 'name' => 'aguardando', 'language' => 'pt_BR', 'status' => 'PENDING', 'category' => 'MARKETING',
        'components' => [{ 'type' => 'BODY', 'text' => 'Olá' }] }
    ]
  end
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', message_templates: templates,
                              sync_templates: false, validate_provider_config: false).inbox
  end
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:hook) { captador_hook_for(account, allowed_inbox_ids: inbox.id.to_s) }
  let(:phone) { '+5565999998888' }
  let(:body) do
    {
      lead: { id: 'lead-1', cnpj: '12345678000199', nome: 'Padaria X Ltda', telefone: '(65) 99999-8888', email: 'contato@padariax.com.br' },
      acting_user_id: agent.id,
      inbox_id: inbox.id,
      template: { name: 'prospeccao_b2b_v1', language: 'pt_BR', processed_params: { body: { '1' => 'Padaria X', '2' => 'Panificação' } } }
    }
  end

  before { create(:inbox_member, inbox: inbox, user: agent) }

  def send_lead(payload = body, key: 'envio-0001', **)
    captador_post(path, payload, hook: hook, headers: { 'Idempotency-Key' => key }, **)
  end

  def error_code
    response.parsed_body['error_code']
  end

  def sent_message
    Message.find(response.parsed_body['message_id'])
  end

  def existing_conversation(**attrs)
    contact = create(:contact, account: account, phone_number: phone)
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: phone.delete('+'))
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, **attrs)
  end

  describe 'assinatura e idempotência' do
    it 'recusa assinatura errada com 401' do
      send_lead(secret: 'outro-segredo')

      expect(response).to have_http_status(:unauthorized)
    end

    it 'exige Idempotency-Key' do
      captador_post(path, body, hook: hook)

      expect(response).to have_http_status(:bad_request)
      expect(error_code).to eq('idempotency_key_required')
    end

    it 'repete a mesma resposta para a mesma chave, corpo e uma nova assinatura, sem segunda mensagem' do
      send_lead
      first = response.parsed_body

      expect { send_lead(timestamp: Time.now.to_i + 1) }.not_to change(Message, :count)
      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to eq(first)
    end

    it 'devolve 409 para a mesma chave com outro corpo' do
      send_lead
      send_lead(body.merge(lead: body[:lead].merge(id: 'lead-2')))

      expect(response).to have_http_status(:conflict)
      expect(error_code).to eq('idempotency_conflict')
    end

    it 'não guarda erro: corrigido, o envio passa com a mesma chave' do
      send_lead(body.merge(lead: body[:lead].merge(telefone: '123')))
      expect(error_code).to eq('phone_invalid')

      send_lead
      expect(response).to have_http_status(:created)
    end
  end

  describe 'caixa oficial (WhatsApp Cloud)' do
    it 'cria contato, conversa e HSM em nome do usuário real e carimba o lead' do
      send_lead

      expect(response).to have_http_status(:created)
      result = response.parsed_body
      conversation = account.conversations.find_by!(display_id: result['conversation_id'])
      contact = conversation.contact

      expect(result).to include('contact_id' => contact.id, 'reused' => false)
      expect(result['conversation_url']).to end_with("/app/accounts/#{account.id}/conversations/#{conversation.display_id}")
      expect(conversation.assignee).to eq(agent)
      expect(conversation.contact_inbox.source_id).to eq('5565999998888')
      expect(sent_message.conversation).to eq(conversation)
      expect(sent_message.sender).to eq(agent)
      expect(sent_message).to be_outgoing
      expect(sent_message.content).to eq('Olá! Vi que a Padaria X atua em Panificação.')
      expect(sent_message.additional_attributes['template_params']).to include('name' => 'prospeccao_b2b_v1', 'language' => 'pt_BR')
      expect(contact).to have_attributes(phone_number: phone, name: 'Padaria X Ltda', email: 'contato@padariax.com.br')
      expect(contact.custom_attributes).to include('cnpj' => '12345678000199', 'captador_lead_id' => 'lead-1')
      expect(conversation.custom_attributes).to include('captador_lead_id' => 'lead-1', 'captador_url' => 'https://captador.spx.ia.br/leads/lead-1')
      expect(conversation.label_list).to include('captador')
    end

    it 'usa o preview como texto da bolha quando vem' do
      send_lead(body.merge(preview: 'Olá! Vi que a Padaria X atua em Panificação…'))

      expect(sent_message.content).to eq('Olá! Vi que a Padaria X atua em Panificação…')
    end

    it 'reusa a conversa aberta do contato (200) e mescla os atributos' do
      conversation = existing_conversation(assignee: agent, custom_attributes: { 'origem' => 'site' })

      expect { send_lead }.to change(conversation.messages, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('reused' => true, 'conversation_id' => conversation.display_id)
      expect(conversation.reload.custom_attributes).to include('origem' => 'site', 'captador_lead_id' => 'lead-1')
    end

    it 'não troca o e-mail que o contato já tem' do
      existing_conversation(assignee: agent).contact.update!(email: 'dono@exemplo.com')
      send_lead

      expect(Contact.find(response.parsed_body['contact_id']).email).to eq('dono@exemplo.com')
    end

    it 'recusa modelo que não está aprovado' do
      send_lead(body.merge(template: body[:template].merge(name: 'aguardando', processed_params: {})))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(error_code).to eq('template_not_approved')
    end

    it 'recusa variáveis do corpo que não batem com o modelo' do
      send_lead(body.merge(template: body[:template].merge(processed_params: { body: { '1' => 'Padaria X' } })))

      expect(error_code).to eq('template_params_mismatch')
    end

    it 'recusa telefone que não vira número brasileiro' do
      expect { send_lead(body.merge(lead: body[:lead].merge(telefone: '123'))) }.not_to change(Contact, :count)

      expect(error_code).to eq('phone_invalid')
    end
  end

  describe 'caixa não oficial (WAHA)' do
    let(:inbox) { create(:channel_api, account: account).inbox.tap { |waha| waha.update!(waha_session_name: 'comercial') } }
    let(:waha_body) { body.except(:template).merge(preview: 'Olá, aqui é da Simplex. Podemos conversar?') }

    it 'envia o preview como texto livre, sem modelo' do
      send_lead(waha_body)

      expect(response).to have_http_status(:created)
      expect(sent_message.content).to eq('Olá, aqui é da Simplex. Podemos conversar?')
      expect(sent_message.additional_attributes).not_to have_key('template_params')
      expect(sent_message.conversation.contact_inbox.source_id).to eq('5565999998888@c.us')
    end

    it 'exige o texto' do
      send_lead(waha_body.except(:preview))

      expect(error_code).to eq('content_required')
    end
  end

  describe 'travas da Simplex' do
    let(:other_team) { create(:team, account: account) }
    let(:colleague) { create(:user, account: account, role: :agent) }

    it 'barra com 403 a conversa aberta de outro time, sem escrever nela' do
      conversation = existing_conversation(team: other_team)

      expect { send_lead }.not_to change(conversation.messages, :count)
      expect(response).to have_http_status(:forbidden)
      expect(error_code).to eq('conversation_access_blocked')
      expect(conversation.reload.custom_attributes).not_to have_key('captador_lead_id')
    end

    it 'barra com 403 a conversa isolada de outro agente' do
      inbox.update!(agent_conversation_isolation: true)
      conversation = existing_conversation(assignee: colleague)

      expect { send_lead }.not_to change(conversation.messages, :count)
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('meta', 'current_assignee', 'id')).to eq(colleague.id)
    end

    it 'aplica o gate "assumir para responder" também na conversa reutilizada (422)' do
      account.update!(reply_assignment_gate: true)
      conversation = existing_conversation(assignee: colleague)

      expect { send_lead }.not_to change(conversation.messages, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(error_code).to eq('assignment_required')
    end

    it 'com o gate, conversa nova nasce com quem clicou' do
      account.update!(reply_assignment_gate: true)
      send_lead(body.merge(assignee_id: nil))

      expect(response).to have_http_status(:created)
      expect(sent_message.conversation.assignee).to eq(agent)
    end

    it 'responde 409 quando o número já é de outra ficha na caixa Cloud' do
      holder = create(:contact, account: account, name: 'Outra Ficha')
      allow(ContactInboxWithContactBuilder).to receive(:new).and_raise(ContactInboxBuilder::ConflictError.new(holder))
      send_lead

      expect(response).to have_http_status(:conflict)
      expect(error_code).to eq('contact_inbox_conflict')
      expect(response.parsed_body.dig('meta', 'id')).to eq(holder.id)
    end

    it 'recusa contato com opt-out de marketing, sem abrir conversa' do
      contact = create(:contact, account: account, phone_number: phone)
      ContactFlowSuppression.record_opt_out!(contact: contact, account: account)

      expect { send_lead }.not_to change(Conversation, :count)
      expect(error_code).to eq('contact_opted_out')
    end

    it 'recusa número sem WhatsApp' do
      create(:contact, account: account, phone_number: phone, custom_attributes: { 'whatsapp_number_exists' => false })
      send_lead

      expect(error_code).to eq('whatsapp_number_invalid')
    end

    it 'recusa caixa fora de allowed_inbox_ids' do
      hook.update!(settings: hook.settings.merge('allowed_inbox_ids' => ''))
      send_lead

      expect(error_code).to eq('channel_not_allowed')
    end

    it 'recusa caixa que não é WhatsApp, mesmo liberada' do
      widget = create(:inbox, account: account)
      create(:inbox_member, inbox: widget, user: agent)
      hook.update!(settings: hook.settings.merge('allowed_inbox_ids' => "#{inbox.id}, #{widget.id}"))
      send_lead(body.merge(inbox_id: widget.id))

      expect(error_code).to eq('channel_not_allowed')
    end

    it 'recusa caixa somente leitura' do
      inbox.update!(read_only: true)
      send_lead

      expect(error_code).to eq('inbox_read_only')
    end

    it 'recusa quem não é membro da caixa' do
      send_lead(body.merge(acting_user_id: colleague.id))

      expect(response).to have_http_status(:forbidden)
      expect(error_code).to eq('inbox_access_denied')
    end

    it 'responde 404 para usuário ou time de fora da conta' do
      send_lead(body.merge(acting_user_id: create(:user, account: create(:account)).id))
      expect(response).to have_http_status(:not_found)

      send_lead(body.merge(team_id: create(:team).id))
      expect(response).to have_http_status(:not_found)
    end
  end
end
