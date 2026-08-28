require 'rails_helper'

# Bloco 1.16, o sintoma que o visitante ve. `widget/conversations#create` abre uma transacao
# (conversations_controller.rb:10-16) e dentro dela chama ContactIdentifyAction, que provisiona
# as definicoes das chaves que o site mandou. Se a corrida abortar essa transacao, nao se perde
# uma definicao: perde-se a conversa e a primeira mensagem, e o widget recebe 500.
RSpec.describe '/api/v1/widget/conversations sob corrida do auto-provisionamento', type: :request do
  include CustomAttributeRaceHelpers

  self.use_transactional_tests = false

  before(:all) { truncate_all_tables! } # rubocop:disable RSpec/BeforeAfterAll

  let!(:account) { create(:account) }
  let!(:web_widget) { create(:channel_widget, account: account) }
  let!(:contact) { create(:contact, account: account, email: nil) }
  let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
  let(:token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id }).generate_token
  end

  after do
    finish_concurrent_requests!
    truncate_all_tables!
  end

  it 'abre a conversa mesmo quando outra requisicao esta criando a mesma definicao' do
    concurrent_definition_holding(account: account, key: 'carrinho_valor')

    attempts = capture_definition_inserts do
      post '/api/v1/widget/conversations',
           headers: { 'X-Auth-Token' => token },
           params: {
             website_token: web_widget.website_token,
             contact: { name: 'Ana do site', custom_attributes: { carrinho_valor: 4200 } },
             message: { content: 'quero fechar o pedido' }
           },
           as: :json
    end

    # Sem o savepoint isto e 500: o INSERT recusado pelo indice aborta a transacao do
    # controller e `create_conversation` levanta PG::InFailedSqlTransaction.
    expect(response).to have_http_status(:success)
    expect(attempts.size).to eq(1)
    expect(attempts.first).to be_a(ActiveRecord::RecordNotUnique)

    conversation = account.conversations.last
    expect(conversation).to be_present
    # So a mensagem do visitante: as outgoing sao os textos do pre-chat que o widget cria.
    expect(conversation.messages.where(message_type: :incoming).pluck(:content)).to eq(['quero fechar o pedido'])
    expect(contact.reload.custom_attributes).to eq('carrinho_valor' => 4200)
    expect(account.custom_attribute_definitions.where(attribute_key: 'carrinho_valor').count).to eq(1)
  end
end
