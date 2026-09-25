require 'rails_helper'

RSpec.describe 'Conversation redirect reply API (CHAT-155)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:target_inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account), waha_session_name: 'numero-novo') }
  let(:source_inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account), waha_session_name: 'numero-antigo') }
  let(:contact) { create(:contact, account: account, name: 'Juliana', phone_number: '+5565992476302') }
  let!(:conversation) { create(:conversation, account: account, inbox: source_inbox, contact: contact) }

  before do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    source_inbox.update!(read_only: true, read_only_redirect_inbox: target_inbox)
  end

  # A API responde no idioma da conta.
  def t(key, **)
    I18n.t("errors.read_only_inbox.#{key}", locale: account.locale, **)
  end

  def redirect(params = { content: 'Oi, agora e por este numero' })
    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/redirect_reply",
         params: params, headers: admin.create_new_auth_token, as: :json
  end

  it 'sends through the target inbox, notes and resolves the original conversation' do
    redirect

    expect(response).to have_http_status(:success)
    target = target_inbox.conversations.find_by!(display_id: response.parsed_body['conversation_id'])
    expect(target.contact).to eq(contact)
    expect(target.messages.outgoing.last.content).to eq('Oi, agora e por este numero')

    note = conversation.messages.where(private: true).last
    expect(note.content).to eq(t('replied_note', inbox: target_inbox.name, conversation: target.display_id))
    expect(conversation.reload).to be_resolved
    expect(conversation.messages.where(private: false).outgoing).to be_empty
  end

  it 'reuses the open conversation of the contact in the target inbox' do
    redirect
    first_id = response.parsed_body['conversation_id']
    conversation.update!(status: :open)

    expect { redirect(content: 'de novo') }.not_to change(target_inbox.conversations, :count)
    expect(response.parsed_body['conversation_id']).to eq(first_id)
  end

  it 'refuses when the inbox has no redirect inbox' do
    source_inbox.update!(read_only_redirect_inbox: nil)

    redirect

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(t('not_redirectable'))
  end

  it 'refuses a contact without phone' do
    contact.update!(phone_number: nil)

    expect { redirect }.not_to change(Conversation, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(t('contact_without_phone'))
  end

  it 'asks for a template when the official WhatsApp target is outside the 24h window' do
    cloud = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
    source_inbox.update!(read_only_redirect_inbox: cloud)

    expect { redirect }.not_to change(Conversation, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['requires_template']).to be(true)
    expect(conversation.reload).not_to be_resolved
  end

  it 'sends the template when the official WhatsApp target is outside the 24h window' do
    cloud = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
    source_inbox.update!(read_only_redirect_inbox: cloud)
    template = { name: 'retomada', language: 'pt_BR', category: 'UTILITY', processed_params: { body: { '1' => 'Juliana' } } }

    redirect(content: 'Oi Juliana, seguimos por aqui', template_params: template)

    expect(response).to have_http_status(:success)
    sent = cloud.conversations.find_by!(display_id: response.parsed_body['conversation_id']).messages.outgoing.last
    expect(sent.additional_attributes.dig('template_params', 'name')).to eq('retomada')
    expect(conversation.reload).to be_resolved
  end
end
