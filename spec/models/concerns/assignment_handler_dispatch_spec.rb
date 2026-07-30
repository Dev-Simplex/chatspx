require "rails_helper"

# Regressao do "trocou de time mas so aparece com F5" (AGN, conversa 895). saved_change_to_team_id?
# roda no after_COMMIT e reflete apenas o ULTIMO save da transacao. O flow atribui o time e salva a
# conversa de novo dentro da MESMA transacao (assign_team seguido de outro update no with_lock do
# ReplyResumeService): o 2o save zerava o predicado, TEAM_CHANGED nunca era despachado e o
# ActionCableListener nunca fazia o broadcast — o agente seguia vendo o time antigo ate recarregar.
describe AssignmentHandler do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:team) { create(:team, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox) }

  after { Current.reset }

  # Coleta os nomes de evento despachados no bloco, sem impedir o dispatch real.
  def dispatched_during
    names = []
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_wrap_original do |orig, name, *rest|
      names << name
      orig.call(name, *rest)
    end
    yield
    names
  end

  # Save que NAO toca em team_id nem assignee_id — e ele que zerava saved_change_to_team_id?.
  def inert_update!(value)
    conversation.update!(custom_attributes: { "ping" => value })
  end

  it "despacha team.changed mesmo com outro save depois na MESMA transacao" do
    names = dispatched_during do
      Conversation.transaction do
        conversation.update!(team: team)
        inert_update!(1)
      end
    end

    expect(names).to include(Events::Types::TEAM_CHANGED)
  end

  it "despacha team.changed uma unica vez no caso que ja funcionava" do
    names = dispatched_during { conversation.update!(team: team) }

    expect(names.count { |n| n == Events::Types::TEAM_CHANGED }).to eq(1)
  end

  it "nao despacha team.changed quando o time nao muda" do
    names = dispatched_during { inert_update!(2) }

    expect(names).not_to include(Events::Types::TEAM_CHANGED)
  end

  it "nao vaza o flag para uma transacao seguinte" do
    conversation.update!(team: team)

    names = dispatched_during { inert_update!(3) }

    expect(names).not_to include(Events::Types::TEAM_CHANGED)
  end
end
