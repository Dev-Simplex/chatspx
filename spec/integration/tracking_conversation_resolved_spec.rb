require 'rails_helper'

# Bloco 5.03 — o aceite LITERAL, de ponta a ponta: "resolver uma conversa gera o evento com event_id".
#
# O spec do listener chama o listener; este aqui resolve a conversa de verdade e deixa o caminho
# inteiro rodar: Conversation#notify_status_change -> Dispatcher -> AsyncDispatcher ->
# EventDispatcherJob -> TrackingEventListener. E a JUNCAO que os testes de unidade nao cobrem, e e
# onde o defeito mora quando as duas pontas estao certas isoladamente.
RSpec.describe 'Resolver uma conversa gera o evento de tracking', type: :model do
  include ActiveJob::TestHelper

  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: user, status: :open) }

  it 'records chatspx_conversation_resolved with an event_id when the conversation is resolved' do
    perform_enqueued_jobs do
      conversation.update!(status: :resolved)
    end

    event = TrackingEvent.find_by(name: 'chatspx_conversation_resolved', conversation_id: conversation.id)
    expect(event).to be_present
    expect(event.event_id).to match(/\A[0-9a-f-]{36}\z/)
    expect(event.account_id).to eq(account.id)
    expect(event.source).to eq('server')
  end

  it 'does not record anything when the conversation is merely reopened' do
    perform_enqueued_jobs { conversation.update!(status: :resolved) }
    perform_enqueued_jobs { conversation.update!(status: :open) }

    expect(TrackingEvent.where(name: 'chatspx_conversation_resolved').count).to eq(1)
  end
end
