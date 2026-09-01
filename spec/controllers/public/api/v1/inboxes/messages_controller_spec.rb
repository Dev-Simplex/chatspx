require 'rails_helper'

# Ingestao de mensagem pela API publica com foco em conversa de GRUPO de WhatsApp:
# o autor chega embutido no texto e precisa sair de la como dado estruturado
# (content_attributes['group_sender'], contrato C2) sem que a conversa 1:1 mude.
RSpec.describe 'Public Inbox Messages API — grupo de WhatsApp', type: :request do
  let(:session_name) { 'Simplex' }
  let!(:api_channel) { create(:channel_api) }
  let(:inbox) { api_channel.inbox }

  let(:group_contact) { create(:contact, account: api_channel.account, identifier: '556699999999-1634750731@g.us') }
  let(:group_contact_inbox) { create(:contact_inbox, contact: group_contact, inbox: inbox) }
  let(:group_conversation) { create(:conversation, contact: group_contact, contact_inbox: group_contact_inbox, inbox: inbox) }

  let(:direct_contact) { create(:contact, account: api_channel.account, phone_number: '+5566999991234') }
  let(:direct_contact_inbox) { create(:contact_inbox, contact: direct_contact, inbox: inbox) }
  let(:direct_conversation) { create(:conversation, contact: direct_contact, contact_inbox: direct_contact_inbox, inbox: inbox) }

  let(:lid) { '229480102662169' }
  let(:group_content) { "👥 *‎Rogerio José Da Silva (#{lid}@lid)*\n\nQual Wi-Fi está?" }

  # O cache vive no Redis e nao volta com o rollback do banco: limpar dos dois
  # lados mantem a suite estavel na ordem aleatoria do RSpec.
  before do
    inbox.update!(waha_session_name: session_name)
    Redis::Alfred.delete(Whatsapp::LidPhoneCache.key(session_name, lid))
  end

  after { Redis::Alfred.delete(Whatsapp::LidPhoneCache.key(session_name, lid)) }

  def post_message(conversation, contact_inbox, params)
    post "/public/api/v1/inboxes/#{api_channel.identifier}/contacts/#{contact_inbox.source_id}" \
         "/conversations/#{conversation.display_id}/messages",
         params: params
  end

  describe 'POST em conversa de grupo' do
    it 'grava o texto sem o prefixo do autor' do
      post_message(group_conversation, group_contact_inbox, { content: group_content })

      expect(response).to have_http_status(:success)
      expect(group_conversation.messages.last.content).to eq('Qual Wi-Fi está?')
    end

    it 'grava o autor em content_attributes.group_sender' do
      post_message(group_conversation, group_contact_inbox, { content: group_content })

      expect(group_conversation.messages.last.content_attributes['group_sender']).to eq(
        'name' => 'Rogerio José Da Silva', 'lid' => lid, 'phone' => nil
      )
    end

    it 'enfileira a resolucao do telefone fora do request' do
      expect { post_message(group_conversation, group_contact_inbox, { content: group_content }) }
        .to have_enqueued_job(Whatsapp::ResolveGroupSenderPhoneJob)
    end

    it 'nao toca no conteudo quando a mensagem de grupo chega sem prefixo' do
      post_message(group_conversation, group_contact_inbox, { content: 'mensagem simples' })

      message = group_conversation.messages.last
      expect(message.content).to eq('mensagem simples')
      expect(message.content_attributes['group_sender']).to be_nil
    end

    it 'aceita mensagem so com o prefixo (anexo sem legenda)' do
      post_message(group_conversation, group_contact_inbox, { content: "👥 *Tecnologia (267722592149653@lid)*\n" })

      message = group_conversation.messages.last
      expect(message.content).to be_nil
      expect(message.content_attributes['group_sender']['name']).to eq('Tecnologia')
    end

    it 'nao aceita content_attributes vindo do cliente' do
      post_message(group_conversation, group_contact_inbox,
                   { content: group_content, content_attributes: { group_sender: { name: 'Invasor' }, deleted: true } })

      attributes = group_conversation.messages.last.content_attributes
      expect(attributes['group_sender']['name']).to eq('Rogerio José Da Silva')
      expect(attributes['deleted']).to be_nil
    end
  end

  describe 'cache de LID -> telefone' do
    it 'usa o cache na segunda mensagem do mesmo participante, sem enfileirar job' do
      Whatsapp::LidPhoneCache.write(session_name, lid, '5566999991234')

      expect { post_message(group_conversation, group_contact_inbox, { content: group_content }) }
        .not_to have_enqueued_job(Whatsapp::ResolveGroupSenderPhoneJob)

      expect(group_conversation.messages.last.content_attributes['group_sender']['phone']).to eq('5566999991234')
    end
  end

  describe 'quando a infra de apoio esta fora' do
    # O request NUNCA toca a WAHA: o telefone so e buscado no job. Este teste
    # existe para travar isso — se alguem mover a chamada para o request, ele
    # quebra em vez de a ingestao ficar refem do timeout de 8s da WAHA.
    it 'nao chama a WAHA durante a ingestao' do
      expect_any_instance_of(Waha::ApiService).not_to receive(:get_lid_phone_number) # rubocop:disable RSpec/AnyInstance

      post_message(group_conversation, group_contact_inbox, { content: group_content })

      expect(response).to have_http_status(:success)
      expect(group_conversation.messages.last.content_attributes['group_sender']['phone']).to be_nil
    end

    it 'ingere a mensagem mesmo com o Redis fora' do
      allow(Redis::Alfred).to receive(:get).and_raise(Redis::CannotConnectError, 'down')

      post_message(group_conversation, group_contact_inbox, { content: group_content })

      expect(response).to have_http_status(:success)
      expect(group_conversation.messages.last.content).to eq('Qual Wi-Fi está?')
    end
  end

  # A WAHA injeta o prefixo quando `isJidGroup(chatId) || isJidBroadcast(chatId)`.
  # No banco de homologação não existe nenhuma conversa de broadcast hoje — este
  # bloco cobre o caso pelo sinal estrutural, não por dado observado.
  describe 'POST em lista de transmissão (broadcast)' do
    let(:broadcast_contact) do
      create(:contact, account: api_channel.account, phone_number: '+5566988887777',
                       custom_attributes: { 'waha_whatsapp_chat_id' => '120363001122334455@broadcast' })
    end
    let(:broadcast_contact_inbox) { create(:contact_inbox, contact: broadcast_contact, inbox: inbox) }
    let(:broadcast_conversation) do
      create(:conversation, contact: broadcast_contact, contact_inbox: broadcast_contact_inbox, inbox: inbox)
    end

    it 'extrai o autor mesmo com group? false' do
      expect(broadcast_conversation.group?).to be(false)

      post_message(broadcast_conversation, broadcast_contact_inbox, { content: group_content })

      message = broadcast_conversation.messages.last
      expect(message.content).to eq('Qual Wi-Fi está?')
      expect(message.content_attributes['group_sender']['name']).to eq('Rogerio José Da Silva')
    end
  end

  describe 'POST em conversa 1:1 — nada pode mudar' do
    it 'nao cria content_attributes' do
      post_message(direct_conversation, direct_contact_inbox, { content: 'Bom dia' })

      message = direct_conversation.messages.last
      expect(message.content).to eq('Bom dia')
      expect(message.content_attributes).to eq({})
    end

    it 'nao extrai autor mesmo se o texto imitar o formato de grupo' do
      post_message(direct_conversation, direct_contact_inbox, { content: group_content })

      message = direct_conversation.messages.last
      expect(message.content).to eq(group_content)
      expect(message.content_attributes['group_sender']).to be_nil
    end

    it 'nao enfileira job de resolucao' do
      expect { post_message(direct_conversation, direct_contact_inbox, { content: group_content }) }
        .not_to have_enqueued_job(Whatsapp::ResolveGroupSenderPhoneJob)
    end
  end
end
