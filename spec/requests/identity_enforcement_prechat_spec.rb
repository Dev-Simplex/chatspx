require 'rails_helper'

# Bloco 4.16 — portas 3 e 4 do HMAC.
#
# Estes dois endpoints nao tem assinatura e nunca terao: quem digita e o visitante, e o
# segredo do HMAC e do servidor do cliente. Entao o que muda sob enforcement estrito nao e
# a aceitacao da requisicao — e a FUSAO de cadastros, que e onde o dano mora.
RSpec.describe 'portas 3 e 4: pre-chat e input_email', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }

  # O dono do e-mail: cadastro que ja existe, com historico.
  let!(:owner) { create(:contact, account: account, email: 'cliente@corp.com', name: 'Cliente Antigo') }
  let!(:owner_inbox) { create(:contact_inbox, contact: owner, inbox: inbox) }
  let!(:owner_conversation) { create(:conversation, account: account, inbox: inbox, contact: owner, contact_inbox: owner_inbox) }

  # A sessao de quem esta digitando agora.
  let(:visitor) { create(:contact, account: account) }
  let(:visitor_inbox) { create(:contact_inbox, contact: visitor, inbox: inbox) }
  let(:token) do
    Widget::TokenService.new(payload: { source_id: visitor_inbox.source_id, inbox_id: inbox.id }).generate_token
  end

  def prechat_with(email)
    post '/api/v1/widget/conversations',
         params: { website_token: web_widget.website_token,
                   contact: { email: email, name: 'Quem Digitou' },
                   message: { content: 'oi' } },
         headers: { 'X-Auth-Token' => token },
         as: :json
  end

  describe 'PORTA 3 — pre-chat' do
    context 'when enforcement esta estrito' do
      before { inbox.update!(identity_enforcement: 'obrigatorio') }

      it 'cria a conversa: a coleta de e-mail do pre-chat NAO e desligada' do
        prechat_with('cliente@corp.com')

        expect(response).to have_http_status(:success)
      end

      it 'NAO funde: a sessao continua no contato do visitante' do
        prechat_with('cliente@corp.com')

        expect(visitor_inbox.reload.contact_id).to eq(visitor.id)
      end

      it 'NAO entrega o historico do dono do e-mail' do
        prechat_with('cliente@corp.com')

        expect(owner.reload.contact_inboxes.pluck(:id)).to eq([owner_inbox.id])
        expect(owner.conversations.pluck(:id)).to eq([owner_conversation.id])
        expect(visitor.reload.conversations.count).to eq(1)
        expect(visitor.conversations.first.id).not_to eq(owner_conversation.id)
      end

      it 'NAO reivindica o e-mail de outro cadastro para a sessao' do
        prechat_with('cliente@corp.com')

        expect(visitor.reload.email).to be_nil
        expect(owner.reload.email).to eq('cliente@corp.com')
      end

      # A regra e estreita de proposito: so morde quando o campo pertence a OUTRO cadastro.
      it 'visitante novo com e-mail que nao existe segue identificando normalmente' do
        prechat_with('novo@corp.com')

        expect(response).to have_http_status(:success)
        expect(visitor.reload.email).to eq('novo@corp.com')
      end
    end

    context 'when enforcement esta desativado — comportamento identico ao de hoje' do
      before { inbox.update!(identity_enforcement: 'desativado') }

      it 'funde a sessao no cadastro do dono do e-mail' do
        prechat_with('cliente@corp.com')

        expect(response).to have_http_status(:success)
        expect(visitor_inbox.reload.contact_id).to eq(owner.id)
      end
    end

    context 'when enforcement esta observado — nao muda nada, so fica contavel' do
      before { inbox.update!(identity_enforcement: 'observado') }

      it 'funde igual ao desativado' do
        prechat_with('cliente@corp.com')

        expect(response).to have_http_status(:success)
        expect(visitor_inbox.reload.contact_id).to eq(owner.id)
      end

      # A fusao deixa o contact_inbox do dono com hmac_verified false e o dono TEM e-mail,
      # entao o relatorio do 4.15 ja conta esta linha sem precisar de mecanismo novo.
      it 'a fusao aparece no relatorio de enforcement' do
        prechat_with('cliente@corp.com')

        relatorio = Identity::EnforcementReport.new(inbox: inbox.reload).perform
        expect(relatorio[:unverified][:total]).to eq(2)
      end
    end
  end

  describe 'PORTA 4 — input_email' do
    let!(:conversation) do
      create(:conversation, account: account, inbox: inbox, contact: visitor, contact_inbox: visitor_inbox)
    end
    let!(:email_message) do
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       content_type: 'input_email', message_type: :template)
    end

    def answer_input_email(email)
      patch "/api/v1/widget/messages/#{email_message.id}",
            params: { website_token: web_widget.website_token, contact: { email: email } },
            headers: { 'X-Auth-Token' => token },
            as: :json
    end

    context 'when enforcement esta estrito' do
      before { inbox.update!(identity_enforcement: 'obrigatorio') }

      it 'aceita a resposta e guarda o e-mail digitado na mensagem' do
        answer_input_email('cliente@corp.com')

        expect(response).to have_http_status(:success)
        expect(email_message.reload.submitted_email).to eq('cliente@corp.com')
      end

      it 'NAO funde a sessao no cadastro do dono' do
        answer_input_email('cliente@corp.com')

        expect(visitor_inbox.reload.contact_id).to eq(visitor.id)
        expect(visitor.reload.email).to be_nil
      end
    end

    context 'when enforcement esta desativado — comportamento identico ao de hoje' do
      before { inbox.update!(identity_enforcement: 'desativado') }

      it 'funde a sessao no cadastro do dono do e-mail' do
        answer_input_email('cliente@corp.com')

        expect(response).to have_http_status(:success)
        expect(visitor_inbox.reload.contact_id).to eq(owner.id)
      end
    end
  end
end
