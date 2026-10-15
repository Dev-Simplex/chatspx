require 'rails_helper'

# A falha da abertura do lead chega depois, pelo webhook de status: a conversa ganha uma linha
# de atividade com o motivo, para o time saber que o cliente não recebeu nada.
RSpec.describe Spx::LeadAberturaFalhaListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:conversation) { create(:conversation, account: account) }

  def abertura(content_attributes)
    create(:message, account: account, conversation: conversation, inbox: conversation.inbox, message_type: :outgoing,
                     status: :sent, content_attributes: content_attributes)
  end

  def falhar(message, erro)
    message.update!(status: :failed, external_error: erro)
    dados = { message: message, previous_changes: message.previous_changes }
    listener.message_updated(Events::Base.new('message.updated', Time.zone.now, dados))
  end

  def atividades
    conversation.messages.where(message_type: :activity).pluck(:content)
  end

  it 'records the Meta reason in plain language' do
    falhar(abertura(meta_lead_ads_initial: true), '131026: Message undeliverable')

    expect(atividades).to eq(['A abertura do lead não foi entregue: Número não recebe mensagens (sem WhatsApp ou app desatualizado)'])
  end

  it 'keeps the detail when the failure has no Meta code' do
    falhar(abertura(meta_lead_ads_initial: true), 'Template not found or invalid template name')

    expect(atividades.last).to eq('A abertura do lead não foi entregue: Erro no envio (sem código da Meta): ' \
                                  'Template not found or invalid template name')
  end

  it 'ignores the failure of a message that is not a lead opener' do
    falhar(abertura({}), '131026: Message undeliverable')

    expect(atividades).to be_empty
  end

  it 'ignores updates that do not change the status to failed' do
    message = abertura(meta_lead_ads_initial: true)
    message.update!(status: :delivered)
    listener.message_updated(Events::Base.new('message.updated', Time.zone.now,
                                              { message: message, previous_changes: message.previous_changes }))

    expect(atividades).to be_empty
  end
end
