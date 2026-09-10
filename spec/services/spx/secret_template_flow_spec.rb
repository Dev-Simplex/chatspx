require 'rails_helper'

# O caminho inteiro, da tela ate a Meta: a caixa marca o template como sigiloso, a mensagem
# nasce com o valor mascarado, o envio manda o valor REAL para a Meta, e depois que sai o
# valor some do banco. Testa junto porque cada peca sozinha passaria com o furo aberto.
RSpec.describe 'fluxo do template sigiloso', type: :request do
  let(:codigo) { '324074' }
  let!(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:account) { inbox.account }
  let(:agente) { create(:user, account: account, role: :agent) }
  let!(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: '5566999999999') }
  let(:conversation) { create(:conversation, contact_inbox: contact_inbox, inbox: inbox, account: account) }

  let(:template_params) do
    {
      'name' => 'sample_shipping_confirmation',
      'category' => 'AUTHENTICATION',
      'language' => 'en_US',
      'processed_params' => { 'body' => { '1' => codigo } }
    }
  end

  def construir_mensagem
    Messages::MessageBuilder.new(
      agente,
      conversation,
      ActionController::Parameters.new(template_params: template_params)
    ).perform
  end

  # Envia de verdade pelo servico, com a chamada para a Meta trocada por um duble que
  # devolve os parametros que teriam ido no payload.
  def enviar(message)
    enviado = nil
    allow(channel).to receive(:send_template) do |_source_id, info, _msg|
      enviado = info[:parameters]
      'wamid.retorno'
    end
    allow(message.inbox).to receive(:channel).and_return(channel)
    Whatsapp::SendOnWhatsappService.new(message: message).perform
    enviado
  end

  describe 'com o template marcado como sigiloso na caixa' do
    include ActiveJob::TestHelper

    before { inbox.update!(additional_attributes: { 'secret_template_names' => ['sample_shipping_confirmation'] }) }

    it 'grava a mascara, nao o codigo' do
      message = construir_mensagem
      gravado = message.reload.additional_attributes['template_params']

      expect(gravado['processed_params']['body']['1']).to eq(Spx::SecretTemplateParams::MASK)
      expect(gravado['name']).to eq('sample_shipping_confirmation')
    end

    it 'nao deixa o codigo no que vai para o navegador' do
      message = construir_mensagem

      # As duas portas de saida: o serializer REST e o empurrao do websocket.
      expect(message.push_event_data.to_json).not_to include(codigo)
      expect(message.additional_attributes['template_params'].except('secret_params').to_json).not_to include(codigo)
    end

    it 'poe rastro na bolha, que nasceria vazia' do
      expect(construir_mensagem.content).to eq(I18n.t('conversations.secret_template.trace'))
    end

    it 'SUBSTITUI o texto ja renderizado, que e por onde o ContactInviteService vazaria' do
      message = Messages::MessageBuilder.new(
        agente,
        conversation,
        ActionController::Parameters.new(
          template_params: template_params,
          content: "Seu codigo e #{codigo}"
        )
      ).perform

      expect(message.content).to eq(I18n.t('conversations.secret_template.trace'))
      expect(message.content).not_to include(codigo)
    end

    it 'manda o codigo REAL para a Meta e mantem o blob, que o admin vai ler depois' do
      message = construir_mensagem
      enviado = enviar(message)

      texto_enviado = enviado.to_json
      expect(texto_enviado).to include(codigo)
      expect(texto_enviado).not_to include(Spx::SecretTemplateParams::MASK)

      params_finais = message.reload.additional_attributes['template_params']
      expect(params_finais['secret_params']).to be_present
      expect(params_finais['processed_params']['body']['1']).to eq(Spx::SecretTemplateParams::MASK)
    end

    it 'resolve a conversa que nasceu so para levar o disparo' do
      message = construir_mensagem
      enviar(message)

      expect(message.conversation.reload.status).to eq('resolved')
    end

    it 'NAO resolve conversa que ja estava aberta antes' do
      create(:message, conversation: conversation, message_type: :incoming, content: 'oi, tudo bem?')
      message = construir_mensagem
      enviar(message)

      expect(message.conversation.reload.status).to eq('open')
    end

    # O caso que escapou na Fabrica: a conversa #519 existia desde a vespera e servia para
    # empurrar relatorio em PDF. Ninguem tinha FALADO nela, entao a primeira regra
    # ("ninguem conversou aqui") a resolveu. Existir antes basta para nao mexer.
    it 'NAO resolve conversa que ja existia, mesmo sem ninguem ter falado nela' do
      create(:message, conversation: conversation, message_type: :outgoing, content: '',
                       additional_attributes: { 'template_params' => { 'name' => 'outro_disparo' } })
      message = construir_mensagem
      enviar(message)

      expect(message.conversation.reload.status).to eq('open')
    end

    it 'diz o motivo certo do encerramento, em vez de inventar inatividade' do
      message = construir_mensagem
      # A mensagem de atividade nasce num job; sem rodar o job nao ha o que conferir.
      # Só ESTE job, para nao arrastar o resto da fila para dentro do teste.
      perform_enqueued_jobs(only: Conversations::ActivityMessageJob) { enviar(message) }

      atividade = message.conversation.messages.where(message_type: :activity).order(:id).last
      expect(atividade.content).to eq(I18n.t('conversations.activity.status.secret_dispatch_resolved'))
      expect(atividade.content).not_to include('inatividade')
    end

    it 'nao dispara pesquisa de satisfacao para quem so recebeu o codigo' do
      inbox.update!(csat_survey_enabled: true, nps_survey_enabled: true)
      message = construir_mensagem
      enviar(message)

      # A trava e do predicado, entao vale para as duas pesquisas de uma vez.
      expect(Spx::SecretTemplateParams.dispatch_only?(message.conversation.reload)).to be(true)
      expect(message.conversation.messages.where(content_type: %w[input_csat]).count).to eq(0)
    end

    it 'NAO resolve quando alguem ja tinha respondido pela caixa' do
      create(:message, conversation: conversation, message_type: :outgoing, content: 'bom dia!')
      message = construir_mensagem
      enviar(message)

      expect(message.conversation.reload.status).to eq('open')
    end

    it 'FALHA o envio quando o blob nao decifra, em vez de mandar a mascara como codigo' do
      message = construir_mensagem
      params = message.additional_attributes['template_params'].merge('secret_params' => 'blob corrompido')
      message.update!(additional_attributes: message.additional_attributes.merge('template_params' => params))

      allow(message.inbox).to receive(:channel).and_return(channel)
      expect(channel).not_to receive(:send_template)

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(message.reload.status).to eq('failed')
      expect(message.external_error).to include('sigilosos')
    end
  end

  describe 'pela API, que e onde a regra vale de verdade' do
    let(:admin) { create(:user, account: account, role: :administrator) }
    # O agente so enxerga a conversa se for membro da caixa: precondicao do teste, nao
    # objeto referenciado. Criado no before para nao virar `let!` orfao.

    before do
      create(:inbox_member, inbox: inbox, user: agente)
      inbox.update!(additional_attributes: { 'secret_template_names' => ['sample_shipping_confirmation'] })
    end

    def mensagens_como(user)
      get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
          headers: user.create_new_auth_token, as: :json
      response.parsed_body['payload']
    end

    it 'entrega o valor ao administrador e a mascara ao agente' do
      construir_mensagem

      do_admin = mensagens_como(admin).last
      do_agente = mensagens_como(agente).last

      expect(do_admin['content']).to include(codigo)
      expect(do_agente['content']).not_to include(codigo)
      expect(do_agente.to_json).not_to include(codigo)
    end

    it 'nao manda o blob cifrado para ninguem' do
      construir_mensagem

      expect(mensagens_como(admin).to_json).not_to include('secret_params')
      expect(mensagens_como(agente).to_json).not_to include('secret_params')
    end
  end

  # 132001 na Fabrica em 10/09: cada numero e um WABA proprio, e o mesmo texto existe nos
  # dois com nomes diferentes. Mandar o do vizinho voltava da Meta como um codigo que nao
  # diz nada para quem atende.
  describe 'template que nao existe neste numero' do
    let(:params_do_vizinho) do
      { 'name' => 'template_do_outro_numero', 'language' => 'pt_BR',
        'processed_params' => { 'body' => { '1' => 'oi' } } }
    end

    it 'falha ANTES de ir para a Meta, com o motivo escrito' do
      message = Messages::MessageBuilder.new(
        agente, conversation, ActionController::Parameters.new(template_params: params_do_vizinho)
      ).perform

      allow(message.inbox).to receive(:channel).and_return(channel)
      expect(channel).not_to receive(:send_template)

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(message.reload.status).to eq('failed')
      expect(message.external_error).to include('template_do_outro_numero')
      expect(message.external_error).not_to include('132001')
    end

    it 'nao atrapalha o template que EXISTE no canal' do
      message = construir_mensagem
      enviado = enviar(message)

      expect(enviado).to be_present
      expect(message.reload.status).not_to eq('failed')
    end
  end

  describe 'com o template fora da lista' do
    it 'nao mexe em nada: sem mascara, sem blob, sem rastro' do
      message = construir_mensagem
      gravado = message.reload.additional_attributes['template_params']

      expect(gravado['processed_params']['body']['1']).to eq(codigo)
      expect(gravado).not_to have_key('secret_params')
      expect(message.content).to be_blank
    end
  end
end
