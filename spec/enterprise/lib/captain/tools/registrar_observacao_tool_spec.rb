require 'rails_helper'

RSpec.describe Captain::Tools::RegistrarObservacaoTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:tool_context) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }

  # CHAT-163 / REGRA #1: exemplo na descrição vira texto que o modelo copia, e o desta ferramenta
  # ainda era de imobiliária, lido por agentes de todos os clientes.
  it 'descreve a observação sem exemplo copiável' do
    expect(described_class.description).not_to match(/\bex(emplo)?[.:]/i)
  end

  it 'grava a observação como nota privada' do
    tool.perform(tool_context, observacao: '  ponto a notar  ')

    nota = conversation.messages.last
    expect(nota).to be_private
    expect(nota.content).to eq('ponto a notar')
  end
end
