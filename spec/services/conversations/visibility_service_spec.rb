require 'rails_helper'

describe Conversations::VisibilityService do
  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:team_x) { create(:team, account: account) }
  let!(:team_y) { create(:team, account: account) }

  # Agente membro do inbox e do time X
  let!(:agent_x) do
    create(:user, account: account, role: :agent).tap do |user|
      create(:inbox_member, user: user, inbox: inbox)
      create(:team_member, user: user, team: team_x)
    end
  end

  # Agente membro do inbox e do time Y (o "outro time")
  let!(:agent_y) do
    create(:user, account: account, role: :agent).tap do |user|
      create(:inbox_member, user: user, inbox: inbox)
      create(:team_member, user: user, team: team_y)
    end
  end

  # Agente membro do inbox, sem time nenhum
  let!(:agent_without_team) do
    create(:user, account: account, role: :agent).tap do |user|
      create(:inbox_member, user: user, inbox: inbox)
    end
  end

  let!(:outsider) { create(:user, account: account, role: :agent) }
  let!(:admin) { create(:user, account: account, role: :administrator) }

  describe '#visible_to?' do
    context 'when the conversation belongs to team X' do
      subject(:service) { described_class.new(conversation: conversation) }

      let(:conversation) { create(:conversation, account: account, inbox: inbox, team: team_x) }

      it 'is visible to a member of the inbox in the same team' do
        expect(service.visible_to?(agent_x)).to be true
      end

      it 'is NOT visible to a member of the inbox in a different team' do
        expect(service.visible_to?(agent_y)).to be false
      end

      it 'is visible to an agent without any team (the list does not filter by team for them)' do
        expect(service.visible_to?(agent_without_team)).to be true
      end

      it 'is visible to an administrator outside the inbox' do
        expect(service.visible_to?(admin)).to be true
      end

      it 'is NOT visible to a non-member of the inbox' do
        expect(service.visible_to?(outsider)).to be false
      end

      it 'is NOT visible to nil' do
        expect(service.visible_to?(nil)).to be false
      end
    end

    # AssignmentHandler#validate_current_assignee_team (app/models/concerns/assignment_handler.rb:48-50)
    # zera o assignee que não é do time sempre que o team_id muda, e sync_team_from_assignee puxa o
    # time do assignee no caminho inverso. Ou seja: "conversa do time X com assignee do time Y" é um
    # estado que o modelo se recusa a persistir. A cláusula de assignee do service é DEFENSIVA —
    # espelha authorize_team_access (conversations_controller.rb:251) e cobre linha legada/escrita
    # que burlou os callbacks. Por isso o estado é forjado aqui driblando os callbacks de propósito.
    context 'when a cross-team assignee is forced past the model invariant' do
      subject(:service) { described_class.new(conversation: conversation) }

      let(:conversation) do
        create(:conversation, account: account, inbox: inbox, team: team_x).tap do |record|
          record.update_column(:assignee_id, agent_y.id) # rubocop:disable Rails/SkipsModelValidations
          record.reload
        end
      end

      it 'is visible to the assignee (assignment implies access)' do
        expect(service.visible_to?(agent_y)).to be true
      end
    end

    # Caminho naturalmente alcançável para a cláusula de assignee: o assignee sai do inbox.
    context 'when the assignee is no longer a member of the inbox' do
      subject(:service) { described_class.new(conversation: conversation) }

      let(:conversation) do
        create(:conversation, account: account, inbox: inbox, team: nil, assignee: agent_x).tap do |record|
          record.inbox.inbox_members.find_by(user: agent_x).destroy!
          record.reload
        end
      end

      it 'is visible to the assignee even without inbox membership' do
        expect(service.visible_to?(agent_x)).to be true
      end
    end

    context 'when the conversation has no team' do
      subject(:service) { described_class.new(conversation: conversation) }

      let(:conversation) { create(:conversation, account: account, inbox: inbox, team: nil) }

      it 'is visible to every inbox member regardless of team' do
        expect(service.visible_to?(agent_x)).to be true
        expect(service.visible_to?(agent_y)).to be true
        expect(service.visible_to?(agent_without_team)).to be true
      end

      it 'is still NOT visible to a non-member of the inbox' do
        expect(service.visible_to?(outsider)).to be false
      end
    end
  end
end
