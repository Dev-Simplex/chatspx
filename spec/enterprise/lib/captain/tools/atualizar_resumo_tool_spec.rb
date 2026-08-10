require 'rails_helper'

RSpec.describe Captain::Tools::AtualizarResumoTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }

  it 'removes sensitive data before persisting the summary' do
    summary = 'Cliente quer exame. CPF 123.456.789-00, telefone +55 (65) 99999-9999. ' \
              'Link https://example.com/clinic?token=url-secret&expires=123 e token=plain-secret.'

    expect(tool.perform(tool_context, resumo: summary)).to eq('Resumo do atendimento atualizado.')

    persisted = conversation.reload.custom_attributes['resumo_atendimento_ia']
    expect(persisted).to include('Cliente quer exame', '[REDACTED_CPF]', '[REDACTED_PHONE]', '[REDACTED_SIGNED_URL]')
    expect(persisted).not_to include('123.456.789-00', '99999-9999', 'url-secret', 'plain-secret')
  end
end
