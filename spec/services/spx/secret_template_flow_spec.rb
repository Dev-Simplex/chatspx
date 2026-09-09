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

  describe 'com o template marcado como sigiloso na caixa' do
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

    it 'manda o codigo REAL para a Meta e apaga o blob depois do envio' do
      message = construir_mensagem
      enviado = nil

      allow(channel).to receive(:send_template) do |_source_id, info, _msg|
        enviado = info[:parameters]
        'wamid.retorno'
      end
      allow(message.inbox).to receive(:channel).and_return(channel)

      described_class_service = Whatsapp::SendOnWhatsappService.new(message: message)
      described_class_service.perform

      texto_enviado = enviado.to_json
      expect(texto_enviado).to include(codigo)
      expect(texto_enviado).not_to include(Spx::SecretTemplateParams::MASK)

      params_finais = message.reload.additional_attributes['template_params']
      expect(params_finais).not_to have_key('secret_params')
      expect(params_finais['processed_params']['body']['1']).to eq(Spx::SecretTemplateParams::MASK)
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
