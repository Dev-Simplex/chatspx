require 'rails_helper'

# A simulação não pode dizer "Distribuiria" onde a guarda vai pular — é justamente para ver o
# caminho ANTES de subir que ela existe.
RSpec.describe Flows::ActionDescriber do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  # O model Team faz `name.downcase` num before_validation (team.rb:34), entao 'Vendas' vira
  # 'vendas' — as expectativas abaixo usam o nome COMO FICA no banco, nao como foi escrito.
  let(:team) { create(:team, account: account, name: 'Vendas') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, team: team, status: :open) }

  def frase(conv = conversation)
    described_class.new(conversation: conv, account: account)
                   .describe({ 'type' => 'action', 'action_name' => 'distribuir', 'action_params' => [] })[:would]
  end

  it 'diz que distribuiria pelo rodízio do time, nomeando o time' do
    create(:distribuicao_policy, account: account, team: team, pool: [])
    expect(frase).to eq('Distribuiria pelo rodízio do time vendas')
  end

  it 'diz que abriria a fila quando a política é pull' do
    create(:distribuicao_policy, :fila, account: account, team: team, pool: [])
    expect(frase).to start_with('Abriria a fila (pull) do time vendas')
  end

  it 'nega a distribuição quando a conversa não tem time' do
    orfa = create(:conversation, account: account, inbox: inbox, status: :open)
    expect(frase(orfa)).to eq('Não distribuiria: a conversa não está em nenhum time')
  end

  it 'nega a distribuição quando o time não tem política ativa' do
    expect(frase).to eq('Não distribuiria: o time vendas não tem política de distribuição ativa')
  end

  it 'nega a distribuição quando a política está em modo off' do
    create(:distribuicao_policy, account: account, team: team, pool: [], modo: 'off')
    expect(frase).to eq("Não distribuiria: a política do time vendas está no modo 'off'")
  end

  it 'não executa nada: descrever é read-only' do
    create(:distribuicao_policy, account: account, team: team, pool: [])
    expect(Spx::Distribuicao::DistribuirService).not_to receive(:new)
    expect { frase }.not_to change(Spx::Distribuicao::Log, :count)
  end
end
