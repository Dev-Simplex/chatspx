require 'rails_helper'

RSpec.describe TeamMember do
  describe 'associations' do
    it { is_expected.to belong_to(:team) }
    it { is_expected.to belong_to(:user) }
  end

  # A lista de times viaja para o navegador pelo CacheEnabledApiClient, e e nela que vai o
  # `is_member` que o front usa para decidir se mostra a mensagem ou o cadeado. Sem invalidar a
  # chave, entrar num time nao chega na tela: o agente vira membro no banco e continua vendo
  # cadeado nas mensagens do time que acabou de ganhar. Foi o que aconteceu na AGN em 25/08/2026,
  # onde a chave estava em zero desde a criacao da conta.
  describe 'invalidacao do cache de times' do
    let(:account) { create(:account) }
    let(:team) { create(:team, account: account) }
    let(:agent) { create(:user, account: account, role: :agent) }

    it 'renova a chave ao ENTRAR no time' do
      antes = account.cache_keys[:team]
      travel(1.second) { create(:team_member, team: team, user: agent) }
      expect(account.cache_keys[:team]).not_to eq(antes)
    end

    it 'renova a chave ao SAIR do time' do
      membro = create(:team_member, team: team, user: agent)
      antes = account.cache_keys[:team]
      travel(1.second) { membro.destroy! }
      expect(account.cache_keys[:team]).not_to eq(antes)
    end

    # Espelha TeamSupervisor: `is_member` e `is_supervisor` alimentam o mesmo getVisibleTeams
    # no front, e antes disto so o segundo invalidava.
    it 'invalida a mesma chave que o TeamSupervisor invalida' do
      antes = account.cache_keys[:team]
      travel(1.second) { create(:team_supervisor, team: team, user: agent) }
      por_supervisao = account.cache_keys[:team]
      expect(por_supervisao).not_to eq(antes)

      outro = create(:user, account: account, role: :agent)
      travel(2.seconds) { create(:team_member, team: team, user: outro) }
      expect(account.cache_keys[:team]).not_to eq(por_supervisao)
    end
  end
end
