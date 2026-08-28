require 'rails_helper'

# Bloco 1.20, asserção (5): `referer_raw` NÃO é servido ao widget.
#
# Este spec mede o BROADCAST, não o presenter isolado. O destino que interessa é o
# `pubsub_token` do `contact_inbox` — o canal do widget, que roda no navegador do PRÓPRIO
# visitante. O spec que existia antes olhava o corpo do jbuilder do widget, e esse jbuilder
# nunca serializou `additional_attributes`: passava no vácuo.
#
# Todo exemplo aqui carrega o CONTROLE POSITIVO junto, porque "não contém" é asserção
# negativa e passaria sozinha com o campo vazio:
#   (a) o `referer_raw` está MESMO gravado no banco, com valor conhecido; e
#   (b) o token do contact_inbox está MESMO na lista de destinatários do broadcast.
#
# O valor cru é produzido pelo caminho real (a URL `javascript:` que nem escapando vira
# http(s) cai em `referer_raw` pelo `validate_referer_url` do modelo), nunca escrito à mão.
#
# O outro lado do mesmo aceite (o job que REMONTA o payload do banco) está em
# `spec/jobs/action_cable_broadcast_job_referer_raw_spec.rb`.
RSpec.describe ActionCableListener do
  let(:listener) { described_class.instance }
  let(:raw_visitor_url) { 'javascript:alert(document.cookie)' }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) do
    create(:conversation,
           account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
           additional_attributes: { 'referer' => raw_visitor_url, 'browser_language' => 'pt-BR',
                                    'initiated_at' => { 'timestamp' => '2026-08-28' } })
  end

  # Cada entrada é [tokens, event_name, payload] como chegaria ao ActionCableBroadcastJob.
  let(:broadcasts) { [] }

  before do
    admin
    Current.user = nil
    Current.account = nil
    allow(ActionCableBroadcastJob).to receive(:perform_later) do |tokens, event_name, payload|
      broadcasts << [tokens, event_name, payload]
    end
  end

  # Controle positivo (a): o dado cru existe no banco com o valor esperado.
  def expect_something_to_leak
    expect(conversation.reload.additional_attributes['referer_raw']).to eq(raw_visitor_url)
  end

  # Controle positivo (b): o canal do widget está mesmo entre os destinatários.
  def expect_widget_in_audience(tokens)
    expect(tokens).to include(contact_inbox.pubsub_token)
  end

  def dispatch(method_name)
    event_name = :"conversation.#{method_name.to_s.sub('conversation_', '')}"
    listener.public_send(method_name, Events::Base.new(event_name, Time.zone.now, conversation: conversation.reload))
  end

  shared_examples 'um broadcast que não leva a URL crua ao widget' do |method_name|
    it "não expõe referer_raw no payload de ##{method_name}" do
      expect_something_to_leak

      dispatch(method_name)

      tokens, _event_name, payload = broadcasts.last
      expect_widget_in_audience(tokens)

      expect(payload[:additional_attributes]).not_to have_key('referer_raw')
      # Rede de segurança: o valor cru não pode aparecer em NENHUM ramo do payload.
      expect(payload.to_json).not_to include('referer_raw')
      expect(payload.to_json).not_to include('alert(document.cookie)')
    end

    it "preserva o resto de additional_attributes em ##{method_name}" do
      dispatch(method_name)

      _tokens, _event_name, payload = broadcasts.last

      expect(payload[:additional_attributes]['browser_language']).to eq('pt-BR')
      expect(payload[:additional_attributes]['initiated_at']).to eq({ 'timestamp' => '2026-08-28' })
    end
  end

  it_behaves_like 'um broadcast que não leva a URL crua ao widget', :conversation_created
  it_behaves_like 'um broadcast que não leva a URL crua ao widget', :conversation_updated
  it_behaves_like 'um broadcast que não leva a URL crua ao widget', :conversation_status_changed

  describe '#message_created — o contato também está na audiência' do
    let(:message) { create(:message, message_type: 'outgoing', account: account, inbox: inbox, conversation: conversation) }

    it 'não leva a URL crua junto da mensagem' do
      expect_something_to_leak

      listener.message_created(Events::Base.new(:'message.created', Time.zone.now, message: message))

      tokens, _event_name, payload = broadcasts.last
      expect_widget_in_audience(tokens)

      expect(payload.to_json).not_to include('referer_raw')
      expect(payload.to_json).not_to include('alert(document.cookie)')
    end
  end

  # Contrapartida: filtrar o PUSH não pode significar destruir o dado. O painel continua
  # enxergando a URL crua pela API REST — é o diagnóstico que o bloco 1.20 existe para preservar.
  describe 'o agente continua enxergando referer_raw pela API do painel', type: :request do
    it 'devolve referer_raw no GET da conversa' do
      create(:inbox_member, inbox: inbox, user: admin)

      get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['additional_attributes']['referer_raw']).to eq(raw_visitor_url)
    end
  end
end
