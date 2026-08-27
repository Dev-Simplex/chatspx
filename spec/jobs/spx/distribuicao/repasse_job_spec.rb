require 'rails_helper'

# O repasse do modo `assignee` (locação), onde o SLA mede "não respondeu ao cliente" e não "não
# assumiu". Chegou pelo PR #67 sem nenhum teste.
#
# O exemplo mais importante daqui é o do escopo: este job e o VarrerSlaJob rodam no MESMO cron de
# 5 minutos, e se os dois olhassem o mesmo lead cada um repassaria para um corretor diferente,
# duas vezes por rodada.
RSpec.describe Spx::Distribuicao::RepasseJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:team) { create(:team, account: account) }
  let(:dono) { create(:user, account: account, role: :agent) }
  let(:proximo) { create(:user, account: account, role: :agent) }
  let(:gestor) { create(:user, account: account, role: :agent) }

  let(:policy) do
    create(:distribuicao_policy, :com_repasse, account: account, team: team,
                                               modo_posse: 'assignee', sla_assumir_minutos: 30,
                                               sla_respeita_horario: false, # relógio de parede: o objeto de teste aqui é o repasse
                                               pool: [dono, proximo, gestor].map { |u| { 'user_id' => u.id, 'ativo' => true } })
  end

  before do
    [dono, proximo, gestor].each do |u|
      create(:inbox_member, user: u, inbox: inbox)
      create(:team_member, user: u, team: team)
    end
    policy
  end

  def conversa_com_dono(user, designado_em: 2.hours.ago)
    conv = create(:conversation, account: account, inbox: inbox, team: team,
                                 assignee: user, status: :open)
    log = Spx::Distribuicao::Log.create!(
      account_id: account.id, conversation_id: conv.id, chosen_user_id: user.id,
      motivo: 'rodizio', candidatos: [], status: 'assumido',
      designado_em: designado_em, created_at: designado_em
    )
    [conv, log]
  end

  describe 'escopo do job' do
    # Sem isto, cada lead vencido seria repassado DUAS vezes a cada 5 minutos.
    it 'nao encosta em politica de modo designacao, que e territorio do VarrerSlaJob' do
      policy.update!(modo_posse: 'designacao')
      _conv, log = conversa_com_dono(dono)

      described_class.new.perform

      expect(log.reload.status).to eq('assumido')
    end

    it 'ignora politica com repasse_automatico desligado' do
      policy.update!(repasse_automatico: false)
      _conv, log = conversa_com_dono(dono)

      described_class.new.perform

      expect(log.reload.status).to eq('assumido')
    end

    it 'ignora politica desativada' do
      policy.update!(ativo: false)
      _conv, log = conversa_com_dono(dono)

      described_class.new.perform

      expect(log.reload.status).to eq('assumido')
    end
  end

  describe 'quando o dono nao respondeu no prazo' do
    it 'passa a conversa para o proximo do pool' do
      conv, log = conversa_com_dono(dono)

      described_class.new.perform

      expect(log.reload.status).to eq('expirado')
      expect(conv.reload.assignee_id).to eq(proximo.id)
    end

    it 'grava o motivo repasse_sla, que e o que faz a vez ser gasta no rodizio' do
      conv, = conversa_com_dono(dono)

      described_class.new.perform

      expect(Spx::Distribuicao::Log.where(conversation_id: conv.id).order(:id).last.motivo)
        .to eq('repasse_sla')
    end

    it 'nao devolve o lead para quem ja o teve neste ciclo' do
      policy.update!(max_repasses: 0) # sem teto: o teste aqui e a exclusao, nao a escalacao
      conv, = conversa_com_dono(dono)

      described_class.new.perform
      primeiro = conv.reload.assignee_id
      Spx::Distribuicao::Log.where(conversation_id: conv.id).order(:id).last
                            .update!(designado_em: 2.hours.ago)
      described_class.new.perform

      expect(conv.reload.assignee_id).not_to eq(primeiro)
      expect(conv.reload.assignee_id).not_to eq(dono.id)
    end
  end

  describe 'quando o dono ja encostou' do
    it 'nao repassa se ele respondeu ao cliente depois de receber' do
      conv, log = conversa_com_dono(dono)
      create(:message, account: account, inbox: inbox, conversation: conv,
                       message_type: :outgoing, sender: dono, private: false)

      described_class.new.perform

      expect(log.reload.status).to eq('assumido')
      expect(conv.reload.assignee_id).to eq(dono.id)
    end

    # Nota privada não é resposta ao cliente: o lead continua parado do ponto de vista dele.
    it 'nota privada nao conta como resposta' do
      conv, log = conversa_com_dono(dono)
      create(:message, account: account, inbox: inbox, conversation: conv,
                       message_type: :outgoing, sender: dono, private: true)

      described_class.new.perform

      expect(log.reload.status).to eq('expirado')
    end

    it 'nao repassa se a conversa ja mudou de dono por fora' do
      conv, log = conversa_com_dono(dono)
      conv.update!(assignee_id: proximo.id)

      described_class.new.perform

      expect(log.reload.status).to eq('assumido')
    end
  end

  describe 'prazo' do
    it 'nao repassa antes de o SLA vencer' do
      conv, log = conversa_com_dono(dono, designado_em: 5.minutes.ago)

      described_class.new.perform

      expect(log.reload.status).to eq('assumido')
      expect(conv.reload.assignee_id).to eq(dono.id)
    end

    # Fail-closed do JanelaService: time sem expediente conhecido não tem lead circulando de
    # madrugada. É o oposto do caminho de vendas, que preserva o relógio de parede — a diferença
    # é deliberada e mora no parâmetro `sem_agenda`.
    it 'nao repassa quando respeita o expediente e nao ha expediente configurado' do
      policy.update!(sla_respeita_horario: true)
      _conv, log = conversa_com_dono(dono)

      described_class.new.perform

      expect(log.reload.status).to eq('assumido')
    end
  end

  # `max_repasses` tem UMA definicao (Policy#esgotou_repasses?), a mesma do caminho de vendas.
  # Antes deste lote o job tinha a sua propria, que divergia em dois pontos.
  describe 'teto de repasses' do
    # `max_repasses: 1` = o lead pode andar UMA vez. Entao o primeiro vencimento repassa e so o
    # segundo escala. A versao anterior do job escalava ja no primeiro, um repasse cedo demais.
    it 'gasta o teto antes de escalar, e so entao vai para o gestor' do
      policy.update!(max_repasses: 1, pool_esgotado_destino_user_id: gestor.id)
      conv, = conversa_com_dono(dono)

      described_class.new.perform
      expect(conv.reload.assignee_id).to eq(proximo.id)

      Spx::Distribuicao::Log.where(conversation_id: conv.id).order(:id).last
                            .update!(designado_em: 2.hours.ago)
      described_class.new.perform

      expect(conv.reload.assignee_id).to eq(gestor.id)
      expect(Spx::Distribuicao::Log.where(conversation_id: conv.id).order(:id).last.motivo)
        .to eq('escalado_gestor')
    end

    # A migration documenta "0 = sem teto". A versao anterior do job lia `1 >= 0` como esgotado,
    # entao configurar "sem teto" mandava o lead direto para o gestor no primeiro vencimento —
    # exatamente o oposto do configurado.
    it 'max_repasses zero significa SEM TETO, e nao escalar de primeira' do
      policy.update!(max_repasses: 0, pool_esgotado_destino_user_id: gestor.id)
      conv, = conversa_com_dono(dono)

      described_class.new.perform

      expect(conv.reload.assignee_id).to eq(proximo.id)
      expect(Spx::Distribuicao::Log.where(conversation_id: conv.id).order(:id).last.motivo)
        .to eq('repasse_sla')
    end
  end
end
