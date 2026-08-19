require 'rails_helper'

RSpec.describe Spx::Distribuicao::VarrerSlaJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:team) { create(:team, account: account) }
  let(:corretor) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, team: team, status: :open) }

  before do
    create(:team_member, team: team, user: corretor)
    create(:inbox_member, inbox: inbox, user: corretor)
  end

  def designacao(minutos)
    create(:distribuicao_log, :aberta, conversation: conversation, chosen_user_id: corretor.id,
                                       designado_em: minutos.minutes.ago)
  end

  # O default de `repasse_automatico` é false: ligar o cron não pode mexer em conta nenhuma.
  it 'não enfileira nada quando nenhuma política tem repasse ligado' do
    create(:distribuicao_policy, account: account, team: team)
    designacao(120)

    expect { described_class.perform_now }.not_to have_enqueued_job(Spx::Distribuicao::RepassarJob)
  end

  it 'enfileira a designação vencida quando o repasse está ligado' do
    create(:distribuicao_policy, :com_repasse, account: account, team: team, sla_assumir_minutos: 30)
    log = designacao(120)

    expect { described_class.perform_now }
      .to have_enqueued_job(Spx::Distribuicao::RepassarJob).with(log.id)
  end

  it 'ignora quem ainda não venceu nem no relógio de parede' do
    create(:distribuicao_policy, :com_repasse, account: account, team: team, sla_assumir_minutos: 30)
    designacao(5)

    expect { described_class.perform_now }.not_to have_enqueued_job(Spx::Distribuicao::RepassarJob)
  end

  it 'ignora linha já encerrada' do
    create(:distribuicao_policy, :com_repasse, account: account, team: team, sla_assumir_minutos: 30)
    designacao(120).encerrar!('assumido')

    expect { described_class.perform_now }.not_to have_enqueued_job(Spx::Distribuicao::RepassarJob)
  end

  # O filtro grosso usa o MENOR sla entre as políticas ligadas — é o limite inferior seguro.
  it 'usa o menor sla das políticas ligadas como piso da varredura' do
    outro_time = create(:team, account: account)
    create(:distribuicao_policy, :com_repasse, account: account, team: team, sla_assumir_minutos: 240)
    create(:distribuicao_policy, :com_repasse, account: account, team: outro_time, sla_assumir_minutos: 10)
    log = designacao(15)

    expect { described_class.perform_now }
      .to have_enqueued_job(Spx::Distribuicao::RepassarJob).with(log.id)
  end
end
