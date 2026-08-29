require 'rails_helper'

# Bloco 4.13, ACEITE: "webhook criado com inbox_id recebe SO os eventos daquela inbox;
# webhook sem inbox_id continua recebendo tudo".
#
# O filtro em si ja tem spec proprio no listener. O que faltava medir e o caminho que a
# TELA percorre: o `WebhookForm` passou a mandar `inbox_id` no submit, e ninguem tinha
# verificado que esse payload — exatamente com essa forma — chega ao banco, volta no
# `index` e muda a entrega. Cada elo testado sozinho pode estar certo e a corrente
# continuar arrebentada no meio.
RSpec.describe 'webhook preso a uma inbox', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox_a) { create(:inbox, account: account) }
  let(:inbox_b) { create(:inbox, account: account) }

  # A forma REAL do que o formulario emite no submit (WebhookForm#onSubmit).
  def cria_webhook(inbox_id)
    post "/api/v1/accounts/#{account.id}/webhooks",
         params: { webhook: { url: 'https://destino.exemplo.com/h', name: 'Meu webhook',
                              inbox_id: inbox_id, subscriptions: ['conversation_created'] } },
         headers: admin.create_new_auth_token, as: :json
  end

  def urls_entregues(inbox)
    entregues = []
    allow(WebhookJob).to receive(:perform_later) { |url, *| entregues << url }
    evento = Events::Base.new('conversation.created', Time.zone.now,
                              { conversation: create(:conversation, account: account, inbox: inbox) })
    WebhookListener.instance.conversation_created(evento)
    entregues
  end

  it 'grava o inbox_id que a tela mandou' do
    cria_webhook(inbox_a.id)

    expect(response).to have_http_status(:success)
    expect(Webhook.last.inbox_id).to eq(inbox_a.id)
  end

  # O formulario le `value.inbox.id` ao editar. Se o `index` parasse de devolver o objeto
  # aninhado, o seletor abriria em "todas" e salvar desprenderia o webhook em silencio.
  it 'e o index devolve a inbox aninhada, que e o que a tela le para reabrir o seletor' do
    cria_webhook(inbox_a.id)

    get "/api/v1/accounts/#{account.id}/webhooks", headers: admin.create_new_auth_token, as: :json

    corpo = response.parsed_body['payload']['webhooks'].first
    expect(corpo['inbox']).to include('id' => inbox_a.id, 'name' => inbox_a.name)
  end

  it 'so recebe os eventos da inbox escolhida' do
    cria_webhook(inbox_a.id)
    criado = Webhook.last

    expect(urls_entregues(inbox_a)).to include(criado.url)
    expect(urls_entregues(inbox_b)).not_to include(criado.url)
  end

  # `null` e o que o formulario manda em "todas as inboxes".
  it 'sem inbox_id continua recebendo tudo' do
    cria_webhook(nil)
    criado = Webhook.last

    expect(criado.inbox_id).to be_nil
    expect(urls_entregues(inbox_a)).to include(criado.url)
    expect(urls_entregues(inbox_b)).to include(criado.url)
  end

  # T-I5.5: "mesma URL, duas inboxes" e configuracao legitima desde que o filtro valha.
  it 'a mesma URL pode servir duas inboxes' do
    cria_webhook(inbox_a.id)
    cria_webhook(inbox_b.id)

    expect(response).to have_http_status(:success)
    expect(Webhook.where(account: account, url: 'https://destino.exemplo.com/h').count).to eq(2)
  end

  it 'e continua recusando a mesma URL duas vezes na mesma inbox' do
    cria_webhook(inbox_a.id)
    cria_webhook(inbox_a.id)

    expect(response).to have_http_status(:unprocessable_entity)
  end

  # Apontar para inbox de outra conta produziria um webhook que nunca casa com evento
  # nenhum: entrega zero, sem erro em lugar nenhum.
  it 'recusa inbox de outra conta' do
    de_fora = create(:inbox, account: create(:account))

    cria_webhook(de_fora.id)

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
