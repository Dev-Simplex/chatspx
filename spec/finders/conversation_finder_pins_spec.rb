require 'rails_helper'

# Fixar conversa é preferência DE UM ATENDENTE — não existe pin compartilhado.
# O teste que vale mesmo é o do isolamento: o mesmo cenário, rodado pelo colega,
# não pode mudar de ordem nenhuma.
describe ConversationFinder do
  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:colleague) { create(:user, account: account, role: :agent) }

  # A ordem natural (atividade desc) é newest, middle, oldest. Fixar justamente a
  # mais antiga é o que prova que a fixação mandou na ordem: sem o alfinete ela
  # fica no fim da lista.
  let!(:oldest) { create(:conversation, account: account, inbox: inbox, last_activity_at: 3.days.ago) }
  let!(:middle) { create(:conversation, account: account, inbox: inbox, last_activity_at: 2.hours.ago) }
  let!(:newest) { create(:conversation, account: account, inbox: inbox, last_activity_at: 1.minute.ago) }

  let(:params) { { status: 'open' } }

  before do
    # Sem inbox_member a PermissionFilterService zera a lista e qualquer assert de
    # ordem passaria por acidente, comparando vazio com vazio.
    create(:inbox_member, user: agent, inbox: inbox)
    create(:inbox_member, user: colleague, inbox: inbox)
    Current.account = account
  end

  def listed_ids_for(user)
    described_class.new(user, params).perform[:conversations].map(&:id)
  end

  describe '#perform with pinned conversations' do
    it 'sorts by last activity while nobody pinned anything' do
      expect(listed_ids_for(agent)).to eq([newest.id, middle.id, oldest.id])
    end

    it 'brings the pinned one to the top even with more recent activity below it' do
      oldest.toggle_pin_for(agent)

      expect(listed_ids_for(agent)).to eq([oldest.id, newest.id, middle.id])
    end

    it 'does not change the order of any other agent' do
      oldest.toggle_pin_for(agent)

      expect(listed_ids_for(colleague)).to eq([newest.id, middle.id, oldest.id])
    end

    it 'keeps each pin with its own owner' do
      oldest.toggle_pin_for(agent)
      middle.toggle_pin_for(colleague)

      expect(listed_ids_for(agent)).to eq([oldest.id, newest.id, middle.id])
      expect(listed_ids_for(colleague)).to eq([middle.id, newest.id, oldest.id])
    end

    it 'keeps sorting by activity among the pinned ones' do
      oldest.toggle_pin_for(agent)
      middle.toggle_pin_for(agent)

      # As duas fixadas na frente e, entre elas, a de atividade mais recente antes.
      expect(listed_ids_for(agent)).to eq([middle.id, oldest.id, newest.id])
    end

    it 'gives the conversation back its normal position when unpinned' do
      oldest.toggle_pin_for(agent)
      expect(listed_ids_for(agent)).to eq([oldest.id, newest.id, middle.id])

      oldest.toggle_pin_for(agent)

      expect(listed_ids_for(agent)).to eq([newest.id, middle.id, oldest.id])
    end

    it 'stores the pin only against the user who asked for it' do
      oldest.toggle_pin_for(agent)

      expect(oldest.reload.pinned_for?(agent)).to be(true)
      expect(oldest.pinned_for?(colleague)).to be(false)
      expect(ConversationPin.where(conversation: oldest).pluck(:user_id)).to eq([agent.id])
    end
  end

  # "Mesmo se for admin": o administrador enxerga a conta inteira, então é nele que
  # um pin compartilhado apareceria primeiro — e é dele que o pin vazaria para todo
  # mundo. Hierarquia não muda nada: cada um só carrega o próprio alfinete.
  describe '#perform with an administrator in play' do
    let!(:admin) { create(:user, account: account, role: :administrator) }

    it 'leaves the agent list untouched when the administrator pins' do
      oldest.toggle_pin_for(admin)

      expect(listed_ids_for(admin)).to eq([oldest.id, newest.id, middle.id])
      expect(listed_ids_for(agent)).to eq([newest.id, middle.id, oldest.id])
    end

    it 'leaves the administrator list untouched when the agent pins' do
      oldest.toggle_pin_for(agent)

      expect(listed_ids_for(agent)).to eq([oldest.id, newest.id, middle.id])
      expect(listed_ids_for(admin)).to eq([newest.id, middle.id, oldest.id])
    end

    it 'does not let the administrator unpin what the agent pinned' do
      oldest.toggle_pin_for(agent)
      oldest.toggle_pin_for(admin)
      # O admin desfixa a dele — a do agente tem de continuar de pé.
      oldest.toggle_pin_for(admin)

      expect(oldest.reload.pinned_for?(admin)).to be(false)
      expect(oldest.pinned_for?(agent)).to be(true)
      expect(listed_ids_for(agent).first).to eq(oldest.id)
      expect(listed_ids_for(admin)).to eq([newest.id, middle.id, oldest.id])
    end
  end
end
