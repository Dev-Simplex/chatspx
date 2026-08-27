require 'rails_helper'

# A AÇÃO que faltava no SLA do rodízio: até aqui `sla_assumir_minutos` só virava número na tela
# do gestor. Aqui a designação parada passa ao próximo — e, esgotadas as tentativas, ao gestor.
RSpec.describe Spx::Distribuicao::RepasseService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:team) { create(:team, account: account) }
  let(:corretores) { create_list(:user, 3, account: account, role: :agent) }
  let(:gestor) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }

  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, team: team, contact: contact, status: :open)
  end

  let(:policy) do
    create(:distribuicao_policy, :com_repasse, account: account, team: team,
                                               pool: corretores.map { |u| { 'user_id' => u.id, 'ativo' => true } })
  end

  # Designação ABERTA (push, sem primeira resposta) já vencida no relógio de parede.
  def designacao(user, repasse_n: 0, minutos: 40)
    create(:distribuicao_log, :aberta, conversation: conversation,
                                       chosen_user_id: user&.id, repasse_n: repasse_n,
                                       designado_em: minutos.minutes.ago)
  end

  before do
    [*corretores, gestor].each { |u| create(:team_member, team: team, user: u) }
    create(:inbox_member, inbox: inbox, user: gestor)
    corretores.each { |u| create(:inbox_member, inbox: inbox, user: u) }
    policy
  end

  describe 'o caminho feliz: passa para o próximo' do
    it 'expira a designação parada e designa outra pessoa' do
      log = designacao(corretores[0])
      conversation.update!(assignee_id: corretores[0].id)

      resultado = described_class.new(log).call

      expect(resultado.repassou).to be(true)
      expect(resultado.motivo).to eq('repasse_sla')
      expect(log.reload.status).to eq('expirado')
      expect(resultado.destino).not_to eq(corretores[0].id)
    end

    it 'atribui de verdade o novo responsável' do
      log = designacao(corretores[0])
      conversation.update!(assignee_id: corretores[0].id)

      resultado = described_class.new(log).call

      expect(conversation.reload.assignee_id).to eq(resultado.destino)
    end

    it 'grava a nova designação com o contador incrementado' do
      log = designacao(corretores[0])
      described_class.new(log).call

      nova = Spx::Distribuicao::Log.where(conversation_id: conversation.id).order(:id).last
      expect(nova.repasse_n).to eq(1)
      expect(nova.motivo).to eq('repasse_sla')
    end

    # SPEC §7.2: quem tinha prioridade e deixou vencer devolve o lead ao rodízio normal. Sem
    # isto a continuidade reescolheria o mesmo consultor e o repasse viraria loop.
    it 'não devolve o lead a quem deixou vencer, mesmo com continuidade ligada' do
      policy.update!(continuidade_ativa: true, continuidade_dias: 30)
      create(:conversation, account: account, inbox: inbox, team: team, contact: contact,
                            assignee_id: corretores[0].id, last_activity_at: 1.day.ago)
      log = designacao(corretores[0])

      resultado = described_class.new(log).call

      expect(resultado.destino).not_to eq(corretores[0].id)
    end

    it 'não repassa duas vezes para a mesma pessoa no mesmo ciclo' do
      primeiro = described_class.new(designacao(corretores[0])).call
      aberta = Spx::Distribuicao::Log.designacao_aberta(conversation.id)
      aberta.update!(designado_em: 40.minutes.ago)

      segundo = described_class.new(aberta).call

      expect(segundo.destino).not_to eq(primeiro.destino)
      expect(segundo.destino).not_to eq(corretores[0].id)
    end
  end

  describe 'escalação' do
    it 'vai para o destino fixo quando o teto de repasses estoura' do
      policy.update!(max_repasses: 1, pool_esgotado_destino_user_id: gestor.id)
      log = designacao(corretores[0], repasse_n: 1)

      resultado = described_class.new(log).call

      expect(resultado.motivo).to eq('escalado_gestor')
      expect(conversation.reload.assignee_id).to eq(gestor.id)
    end

    it 'não escala para quem não é do time (a atribuição seria descartada em silêncio)' do
      forasteiro = create(:user, account: account, role: :agent)
      policy.update!(max_repasses: 1, pool_esgotado_destino_user_id: forasteiro.id)

      resultado = described_class.new(designacao(corretores[0], repasse_n: 1)).call

      expect(resultado.repassou).to be(false)
      expect(resultado.motivo).to eq('destino_fora_do_time')
    end

    it 'sem destino configurado apenas expira e devolve o lead à fila' do
      policy.update!(max_repasses: 1, pool_esgotado_destino_user_id: nil)
      log = designacao(corretores[0], repasse_n: 1)

      resultado = described_class.new(log).call

      expect(resultado.repassou).to be(false)
      expect(log.reload.status).to eq('expirado')
    end
  end

  describe 'guardas' do
    it 'não faz nada com o repasse desligado (SLA segue só como medida)' do
      policy.update!(repasse_automatico: false)
      log = designacao(corretores[0])

      expect(described_class.new(log).call.motivo).to eq('sem_policy')
      expect(log.reload.status).to eq('designado')
    end

    it 'não faz nada quando o prazo ainda não venceu' do
      log = designacao(corretores[0], minutos: 5)

      expect(described_class.new(log).call.motivo).to eq('nao_venceu')
      expect(log.reload.status).to eq('designado')
    end

    it 'não repassa quando alguém já respondeu ao cliente' do
      log = designacao(corretores[0])
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :outgoing, sender: corretores[0], content: 'oi')

      resultado = described_class.new(log).call

      expect(resultado.repassou).to be(false)
      expect(resultado.motivo).to eq('ja_engajada')
    end

    it 'não repassa conversa já resolvida' do
      log = designacao(corretores[0])
      conversation.update!(status: :resolved)

      expect(described_class.new(log).call.motivo).to eq('ja_engajada')
    end

    it 'ignora linha já fechada (idempotência do job)' do
      log = designacao(corretores[0])
      log.encerrar!('assumido')

      expect(described_class.new(log).call.motivo).to eq('log_fechado')
    end

    # O relógio comercial é o que impede punir quem estava fora do expediente.
    it 'não vence fora do expediente' do
      inbox.update!(working_hours_enabled: true, timezone: Time.zone.name)
      inbox.working_hours.destroy_all
      (0..6).each { |wday| inbox.working_hours.create!(day_of_week: wday, closed_all_day: true) }
      log = designacao(corretores[0], minutos: 600)

      expect(described_class.new(log).call.motivo).to eq('nao_venceu')
    end
  end

  describe 'modo fila (pull)' do
    it 'escala direto para o gestor — uma fila não tem "próximo"' do
      policy.update!(modo: 'fila', pool_esgotado_destino_user_id: gestor.id)
      log = designacao(nil)

      resultado = described_class.new(log).call

      expect(resultado.motivo).to eq('escalado_gestor')
      expect(conversation.reload.assignee_id).to eq(gestor.id)
    end
  end
end
