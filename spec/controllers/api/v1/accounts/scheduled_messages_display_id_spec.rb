require 'rails_helper'

# CHAT-175: a conversa é conhecida no front pelo display_id; filtrar por ele não pode trazer
# agendamento de outra conversa cujo id interno coincida com esse número.
RSpec.describe 'Scheduled Messages API filtered by conversation_display_id', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:other_conversation) { create(:conversation, account: account, inbox: inbox) }

  before do
    ScheduledMessage.create!(conversation: conversation, inbox: inbox, message: 'desta conversa',
                             scheduled_at: 2.hours.from_now, status: :pending)
    ScheduledMessage.create!(conversation: other_conversation, inbox: inbox, message: 'de outra conversa',
                             scheduled_at: 2.hours.from_now, status: :pending)
  end

  it 'returns only the messages of the conversation with that display_id' do
    get "/api/v1/accounts/#{account.id}/scheduled_messages",
        params: { conversation_display_id: conversation.display_id, status: 'pending' },
        headers: admin.create_new_auth_token,
        as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.pluck('message')).to eq(['desta conversa'])
  end
end
