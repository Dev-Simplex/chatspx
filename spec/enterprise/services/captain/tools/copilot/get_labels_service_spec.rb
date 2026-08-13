require 'rails_helper'

# Esta é a lista de onde o modelo tira o texto que passa pro `add_label`. Ela ignorava
# `Label.visibility` — feature deste fork — e devolvia label `personal` de outro usuário e
# label `team` de time do qual o operador não participa, justamente o que a tela esconde.
RSpec.describe Captain::Tools::Copilot::GetLabelsService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:other_agent) { create(:user, account: account) }
  let(:service) { described_class.new(assistant, user: agent) }

  let(:team) { create(:team, account: account) }
  let(:other_team) { create(:team, account: account) }

  before do
    create(:label, account: account, title: 'publica', visibility: :everyone)
    create(:label, account: account, title: 'minha', visibility: :personal, created_by: agent)
    create(:label, account: account, title: 'do-outro', visibility: :personal, created_by: other_agent)
    create(:label, account: account, title: 'meu-time', visibility: :team, team: team)
    create(:label, account: account, title: 'outro-time', visibility: :team, team: other_team)
    create(:team_member, team: team, user: agent)
  end

  describe '#execute' do
    it 'hides personal labels of other users' do
      expect(service.execute).not_to include('do-outro')
    end

    it 'hides team labels of teams the user does not belong to' do
      expect(service.execute).not_to include('outro-time')
    end

    it 'lists the labels the user can actually see' do
      result = service.execute

      expect(result).to include('publica', 'minha', 'meu-time')
    end

    it 'lists everything for an administrator' do
      admin = create(:user, :administrator, account: account)

      expect(described_class.new(assistant, user: admin).execute).to include('do-outro', 'outro-time')
    end

    it 'does not leak labels from another account' do
      create(:label, account: create(:account), title: 'de-outra-conta', visibility: :everyone)

      expect(service.execute).not_to include('de-outra-conta')
    end
  end

  # Era o único tool do copilot sem `active?`: ficava registrado até numa sessão sem usuário
  # (o gatilho `#copilot` monta o ChatService sem user_id), e aí não há de quem respeitar a
  # visibilidade — a chamada nem teria como filtrar.
  describe '#active?' do
    it 'is active for a member of the account' do
      expect(service.active?).to be true
    end

    it 'is inactive when the session has no user' do
      expect(described_class.new(assistant).active?).to be false
    end
  end
end
