require 'rails_helper'

# Nó `distribuir` (Flows::DistribuicaoAction): o Motor de Distribuição virou um BLOCO do canvas
# em vez de uma flag global invisível (`gatilho_sem_ia`). O que este arquivo protege é o contrato
# que o nó tem e o listener não tinha: cada caminho em que NADA é distribuído sai como `skipped`
# com um CÓDIGO próprio — nunca como `success`. Guarda que devolve success é o que faz o painel
# Execuções mentir ("distribuiu" com ninguém do outro lado).
RSpec.describe Flows::ActionService do
  let(:account) { create(:account) }
  let(:flow) { create(:flow, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:team) { create(:team, account: account) }
  let(:corretores) { create_list(:user, 2, account: account, role: :agent) }
  let(:pool) { corretores.map { |user| { 'user_id' => user.id, 'ativo' => true } } }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, team: team, status: :open) }

  after { Current.reset }

  before do
    corretores.each do |user|
      create(:team_member, team: team, user: user)
      create(:inbox_member, inbox: inbox, user: user)
    end
  end

  def executar(conv = conversation)
    described_class.new(flow: flow, conversation: conv).execute({ 'type' => 'action', 'action_name' => 'distribuir', 'action_params' => [] })
  end

  # Sem isto o flow NEM SALVA: Flow#definition_action_names recusa action_name fora da whitelist.
  it 'está no vocabulário do motor (senão o flow com o nó não passa na validação)' do
    expect(Flow::BASE_ACTION_NAMES).to include('distribuir')
  end

  describe 'quando há política ativa em modo rodízio' do
    before { create(:distribuicao_policy, account: account, team: team, pool: pool) }

    it 'entrega a conversa a alguém do pool e reporta sucesso' do
      result = executar

      expect(result.status).to eq(:success)
      expect(conversation.reload.assignee_id).to be_in(corretores.map(&:id))
    end

    it 'registra a decisão no livro-razão, com o motivo' do
      expect { executar }.to change(Spx::Distribuicao::Log, :count).by(1)

      log = Spx::Distribuicao::Log.where(conversation_id: conversation.id).order(:id).last
      expect(log.chosen_user_id).to be_in(corretores.map(&:id))
      expect(log.motivo).to eq('rodizio')
    end

    it 'anda com o ponteiro do rodízio — o próximo lead é de outra pessoa' do
      executar
      primeiro = conversation.reload.assignee_id

      outra = create(:conversation, account: account, inbox: inbox, team: team, status: :open)
      executar(outra)

      expect(outra.reload.assignee_id).to be_present
      expect(outra.reload.assignee_id).not_to eq(primeiro)
    end
  end

  # Pull: ninguém é escolhido DE PROPÓSITO, e a linha aberta é o relógio do SLA da fila. É a ação
  # fazendo exatamente o que devia — logo `success`, não `skipped`.
  describe 'quando a política está em modo fila (pull)' do
    before { create(:distribuicao_policy, :fila, account: account, team: team, pool: pool) }

    it 'abre a fila e reporta sucesso mesmo sem escolher ninguém' do
      result = executar

      expect(result.status).to eq(:success)
      expect(conversation.reload.assignee_id).to be_nil
      expect(Spx::Distribuicao::Log.abertas.where(conversation_id: conversation.id).count).to eq(1)
    end
  end

  describe 'guardas — cada uma com o seu código' do
    it "pula com 'sem_time' quando a conversa não está em nenhum time" do
      orfa = create(:conversation, account: account, inbox: inbox, status: :open)
      result = executar(orfa)

      expect(result.status).to eq(:skipped)
      expect(result.error).to be_a(Flows::StepSkip)
      expect(result.error.code).to eq('sem_time')
    end

    it "pula com 'sem_politica' quando o time não tem política" do
      result = executar

      expect(result.status).to eq(:skipped)
      expect(result.error.code).to eq('sem_politica')
    end

    it "pula com 'sem_politica' quando a política existe mas está inativa" do
      create(:distribuicao_policy, account: account, team: team, pool: pool, ativo: false)
      result = executar

      expect(result.status).to eq(:skipped)
      expect(result.error.code).to eq('sem_politica')
    end

    it "pula com 'modo_off' quando a política está em modo off" do
      create(:distribuicao_policy, account: account, team: team, pool: pool, modo: 'off')
      result = executar

      expect(result.status).to eq(:skipped)
      expect(result.error.code).to eq('modo_off')
    end

    it "pula com 'modo_off' quando a política está em modo online (reservado, ainda no-op)" do
      create(:distribuicao_policy, account: account, team: team, pool: pool, modo: 'online')
      result = executar

      expect(result.status).to eq(:skipped)
      expect(result.error.code).to eq('modo_off')
    end

    it "pula com 'sem_pool' quando ninguém do pool está disponível" do
      create(:distribuicao_policy, account: account, team: team, pool: [])
      result = executar

      expect(result.status).to eq(:skipped)
      expect(result.error.code).to eq('sem_pool')
      expect(conversation.reload.assignee_id).to be_nil
    end

    # O DistribuirService engole a própria exceção (loga "[Distribuicao] …" e devolve noop mudo).
    # Sem decisão E sem motivo não é sucesso: vira um skip triável em vez de sumir.
    it "pula com 'erro_motor' quando o Motor devolve um noop sem motivo" do
      create(:distribuicao_policy, account: account, team: team, pool: pool)
      allow(Spx::Distribuicao::DistribuirService).to receive(:new).and_return(
        instance_double(Spx::Distribuicao::DistribuirService,
                        call: Spx::Distribuicao::DistribuirService::Result.new(decidido: false, user_id: nil, motivo: nil))
      )
      result = executar

      expect(result.status).to eq(:skipped)
      expect(result.error.code).to eq('erro_motor')
    end

    # Um skip é guarda INTENCIONAL, não incidente: não pode virar ruído no Sentry.
    it 'não manda skip para o rastreador de exceções' do
      conversation && flow # materializa o cenário ANTES de espiar o rastreador

      expect(ChatwootExceptionTracker).not_to receive(:new)
      expect(executar.status).to eq(:skipped)
    end
  end
end
