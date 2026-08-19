require 'rails_helper'

# 6.02 — o custo mostrado ANTES de rodar, na unidade em que o produto cobra.
RSpec.describe Captain::Eval::CostEstimatorService do
  let(:account) { create(:account, custom_attributes: { plan_name: 'startups' }) }
  let(:assistant) { create(:captain_assistant, account: account) }

  it 'counts one response per active case — é assim que o produto cobra' do
    create_list(:captain_eval_case, 3, captain_assistant: assistant, account: account)
    create(:captain_eval_case, captain_assistant: assistant, account: account, ativo: false)

    estimativa = described_class.new(assistant: assistant).perform

    expect(estimativa[:casos]).to eq(3)
    expect(estimativa[:respostas]).to eq(3)
  end

  it 'estimates tokens and says out loud that it is an estimate' do
    create(:captain_eval_case, captain_assistant: assistant, account: account)

    estimativa = described_class.new(assistant: assistant).perform

    expect(estimativa[:tokens_estimados]).to be > described_class::SAIDA_ESTIMADA_TOKENS
    expect(estimativa[:base_da_estimativa]).to include('caracteres por token')
  end

  it 'grows with the number of cases' do
    create(:captain_eval_case, captain_assistant: assistant, account: account)
    um = described_class.new(assistant: assistant).perform[:tokens_estimados]
    create(:captain_eval_case, captain_assistant: assistant, account: account)
    dois = described_class.new(assistant: assistant).perform[:tokens_estimados]

    expect(dois).to be > um
  end

  it 'shows the account balance and flags when the run would not fit in it' do
    account.update!(limits: { 'captain_responses' => 2 })
    create_list(:captain_eval_case, 3, captain_assistant: assistant, account: account)

    estimativa = described_class.new(assistant: assistant).perform

    expect(estimativa[:saldo][:disponivel]).to eq(2)
    expect(estimativa[:excede_saldo]).to be(true)
  end

  it 'does not flag when the run fits' do
    account.update!(limits: { 'captain_responses' => 50 })
    create(:captain_eval_case, captain_assistant: assistant, account: account)

    expect(described_class.new(assistant: assistant).perform[:excede_saldo]).to be(false)
  end

  it 'never calls an LLM to estimate' do
    create(:captain_eval_case, captain_assistant: assistant, account: account)
    expect(Captain::Assistant::AgentRunnerService).not_to receive(:new)

    described_class.new(assistant: assistant).perform
  end
end
