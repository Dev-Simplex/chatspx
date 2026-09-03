# frozen_string_literal: true

require 'rails_helper'

# 4.18 — O ACEITE, percorrido como o visitante o percorre.
#
# "Visitante preenche nome e e-mail, abandona no 3º campo e fecha a aba: o lead existe no
# painel marcado como incompleto, com a etapa em que parou; retomar na mesma sessao NAO
# duplica o registro; o lead incompleto NAO dispara automacao, campanha nem webhook de
# conversa (ele nao e uma conversa)."
RSpec.describe '/api/v1/widget/partial_leads (4.18)', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:contact) { create(:contact, account: account, email: nil, phone_number: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
  let(:token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id }).generate_token
  end

  after { Current.reset }

  def enable_capture!
    account.update!(internal_attributes: account.internal_attributes.merge('partial_lead_capture_enabled' => true))
  end

  # O visitante responde um campo. `step`/`step_key` sao a ETAPA EM QUE ELE ESTA — o
  # widget manda o primeiro campo ainda vazio (ver PreChat/Form.vue#stoppedAt).
  def responde(answers, step:, step_key:)
    post '/api/v1/widget/partial_leads',
         params: { website_token: web_widget.website_token, answers: answers, step: step, step_key: step_key },
         headers: { 'X-Auth-Token' => token },
         as: :json
  end

  describe 'gravando a resposta parcial' do
    before { enable_capture! }

    it 'grava nome e e-mail e a etapa em que a pessoa parou' do
      expect { responde({ fullName: 'Walisson' }, step: 2, step_key: 'emailAddress') }
        .to change(WidgetPartialLead, :count).by(1)

      expect(response).to have_http_status(:success)
      lead = WidgetPartialLead.last
      expect(lead.answers).to eq({ 'fullName' => 'Walisson' })
      expect(lead.step_reached).to eq(2)
      expect(lead.step_key).to eq('emailAddress')
      expect(lead.session_id).to eq(contact_inbox.source_id)
    end

    it 'RETOMAR NA MESMA SESSAO NAO DUPLICA: mescla as respostas numa unica linha' do
      responde({ fullName: 'Walisson' }, step: 2, step_key: 'emailAddress')

      expect { responde({ emailAddress: 'walisson@empresa.com.br' }, step: 3, step_key: 'phoneNumber') }
        .not_to change(WidgetPartialLead, :count)

      lead = WidgetPartialLead.last
      expect(lead.answers).to eq({ 'fullName' => 'Walisson', 'emailAddress' => 'walisson@empresa.com.br' })
      expect(lead.step_reached).to eq(3)
      expect(lead.step_key).to eq('phoneNumber')
    end

    it 'campo esvaziado pela pessoa some do registro — nao guardamos o que ela retirou' do
      responde({ fullName: 'Walisson', emailAddress: 'x@y.com' }, step: 3, step_key: 'phoneNumber')
      responde({ emailAddress: '' }, step: 2, step_key: 'emailAddress')

      expect(WidgetPartialLead.last.answers).to eq({ 'fullName' => 'Walisson' })
    end

    it 'a sessao vem do TOKEN, nunca do corpo — um cliente adulterado nao escreve na sessao alheia' do
      responde({ fullName: 'Walisson', session_id: 'sessao-de-outro' }, step: 1, step_key: 'fullName')

      expect(WidgetPartialLead.last.session_id).to eq(contact_inbox.source_id)
    end

    it 'nao deixa o navegador escrever um jsonb arbitrario: corta em 8 campos e trunca os valores' do
      answers = 12.times.to_h { |i| ["campo#{i}", 'v' * 900] }
      responde(answers, step: 1, step_key: 'campo0')

      lead = WidgetPartialLead.last
      expect(lead.answers.size).to eq(8)
      expect(lead.answers.values.map(&:length).uniq).to eq([500])
    end

    it 'nao explode nem grava quando nao ha resposta nenhuma' do
      expect { responde({}, step: 1, step_key: 'fullName') }.not_to change(WidgetPartialLead, :count)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'com a captura DESLIGADA (o padrao, e o comportamento de hoje)' do
    it 'responde 200 e nao grava nada — o widget nao conhece a configuracao do cliente' do
      expect(account.internal_attributes['partial_lead_capture_enabled']).to be_nil

      expect { responde({ fullName: 'Walisson' }, step: 1, step_key: 'fullName') }
        .not_to change(WidgetPartialLead, :count)
      expect(response).to have_http_status(:success)
    end
  end

  describe 'o lead incompleto NAO e uma conversa' do
    let!(:regra) do
      create(:automation_rule, account: account, event_name: 'conversation_created', active: true,
                               actions: [{ action_name: 'add_label', action_params: ['veio-da-automacao'] }])
    end
    let!(:webhook) { create(:webhook, account: account, url: 'https://exemplo.test/hook', subscriptions: ['conversation_created']) }

    before { enable_capture! }

    it 'nao cria conversa, nao dispara automacao e nao emite webhook de conversa' do
      clear_enqueued_jobs

      expect do
        responde({ fullName: 'Walisson', emailAddress: 'walisson@empresa.com.br' }, step: 3, step_key: 'phoneNumber')
        perform_enqueued_jobs
      end.not_to change(Conversation, :count)

      expect(WidgetPartialLead.count).to eq(1)
      expect(regra).to be_present # a regra existe e esta ativa: nao disparou por falta de conversa
      expect(webhook).to be_present
      # Nenhuma requisicao externa foi feita: o WebMock levantaria se um webhook saisse.
      expect(a_request(:post, 'https://exemplo.test/hook')).not_to have_been_made
    end

    # Depois do abandono confirmado o lead APARECE NO PAINEL — como contato marcado, nunca
    # como conversa.
    it 'apos a janela de abandono o contato aparece marcado como incompleto, com a etapa' do
      responde({ fullName: 'Walisson', emailAddress: 'walisson@empresa.com.br' }, step: 3, step_key: 'phoneNumber')
      WidgetPartialLead.last.update!(last_answered_at: 30.minutes.ago)

      expect { Widget::PartialLeads::SweepJob.perform_now(account.id) }.not_to change(Conversation, :count)

      marcado = contact.reload
      expect(marcado.email).to eq('walisson@empresa.com.br')
      expect(marcado.custom_attributes['widget_lead_incomplete']).to be(true)
      expect(marcado.custom_attributes['widget_lead_step']).to eq(3)
      expect(marcado.custom_attributes['widget_lead_step_name']).to eq('phoneNumber')
      expect(marcado.label_list).to include('lead-incompleto')
    end
  end

  describe 'quando o visitante CONCLUI o pre-chat' do
    before { enable_capture! }

    it 'a resposta parcial deixa de ser um lead incompleto (e a linha fica, para o relatorio)' do
      responde({ fullName: 'Walisson', emailAddress: 'walisson@empresa.com.br' }, step: 3, step_key: 'phoneNumber')

      post api_v1_widget_messages_url,
           params: { website_token: web_widget.website_token,
                     message: { content: 'oi', timestamp: Time.current.to_i } },
           headers: { 'X-Auth-Token' => token },
           as: :json

      expect(response).to have_http_status(:success)
      lead = WidgetPartialLead.last
      expect(lead.completed_at).to be_present
      expect(WidgetPartialLead.count).to eq(1)

      # E o varredor nao o materializa mais como incompleto.
      lead.update!(last_answered_at: 30.minutes.ago)
      Widget::PartialLeads::SweepJob.perform_now(account.id)
      expect(contact.reload.custom_attributes['widget_lead_incomplete']).to be_nil
    end
  end
end
