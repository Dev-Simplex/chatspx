require 'rails_helper'

# A falha de entrega da abertura chega depois, pelo webhook: a conversa de origem precisa saber,
# para a IA pedir a correção do número ao cliente.
RSpec.describe Spx::TrocaDeCanalFalhaListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:origem) { create(:conversation, account: account) }
  let(:destino) do
    caixa = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
    caixa.update!(name: 'Geral')
    create(:conversation, account: account, inbox: caixa)
  end

  def abertura(marcas)
    create(:message, account: account, conversation: destino, inbox: destino.inbox, message_type: :outgoing,
                     status: :sent, additional_attributes: marcas)
  end

  def falhar(message)
    message.update!(status: :failed, external_error: '131026: Message undeliverable')
    dados = { message: message, previous_changes: message.previous_changes }
    listener.message_updated(Events::Base.new('message.updated', Time.zone.now, dados))
  end

  it 'avisa a origem com nota e com o atributo que a IA lê' do
    falhar(abertura({ 'troca_de_canal_origem_id' => origem.id }))

    aviso = origem.reload.custom_attributes['acionamento_falhou']
    expect(aviso).to include('canal Geral não foi entregue (131026: Message undeliverable)')
    expect(origem.messages.where(private: true).last.content).to eq(aviso)
  end

  it 'ignora falha de mensagem que não é abertura de troca de canal' do
    falhar(abertura({}))

    expect(origem.reload.custom_attributes).not_to have_key('acionamento_falhou')
  end
end
