# frozen_string_literal: true

require 'rails_helper'

# O filtro por time mora na association `conversation.messages`, que não conhece o viewer.
# A exceção por agente obriga a association a ler `Current.user`, e a guarda desse acesso é
# o ponto mais perigoso da task: contexto SEM viewer (job de relatório, API pública, widget)
# tem de MANTER o filtro de hoje.
RSpec.describe Conversation do
  let!(:account) { create(:account) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:team_a) { create(:team, account: account) }
  let!(:team_b) { create(:team, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, team: team_a) }

  # mensagem sem time: pública, sempre visível
  let!(:public_msg) do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming).tap do |message|
      message.update_column(:team_id, nil) # rubocop:disable Rails/SkipsModelValidations
    end
  end
  # mensagem do time A (o time atual da conversa)
  let!(:from_team_a) do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: agent)
  end
  # mensagem de OUTRO time: é ela que o isolamento esconde
  let!(:from_team_b) do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing,
                     sender: create(:user, account: account, role: :agent)).tap do |message|
      message.update_column(:team_id, team_b.id) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  after { Current.user = nil }

  def visible_message_ids
    conversation.reload.messages.map(&:id)
  end

  context 'when the inbox does not have team isolation enabled' do
    it 'shows every message to an agent' do
      Current.user = agent

      expect(visible_message_ids).to include(public_msg.id, from_team_a.id, from_team_b.id)
    end
  end

  context 'when the inbox has team isolation enabled' do
    before { inbox.update!(team_message_isolation: true) }

    # lista de exceções vazia = comportamento de hoje, byte a byte
    it 'hides the other team messages from an agent when there is no exemption' do
      Current.user = agent
      ids = visible_message_ids

      expect(ids).to include(public_msg.id, from_team_a.id)
      expect(ids).not_to include(from_team_b.id)
    end

    # ESTE é o teste que impede um job de relatório passar a enxergar mensagem de outro time
    it 'keeps the filter when there is no Current.user (job, public API, widget)' do
      Current.user = nil
      ids = visible_message_ids

      expect(ids).to include(public_msg.id, from_team_a.id)
      expect(ids).not_to include(from_team_b.id)
    end

    # e continua mantendo o filtro mesmo com uma exceção gravada: sem viewer, ninguém é exceção
    it 'keeps the filter in a job context even when the agent is an exemption' do
      create(:inbox_isolation_exemption, inbox: inbox, user: agent, isolation_type: 'team_message')
      Current.user = nil

      expect(visible_message_ids).not_to include(from_team_b.id)
    end

    it 'keeps the filter for an administrator, as it always did' do
      Current.user = admin

      expect(visible_message_ids).not_to include(from_team_b.id)
    end

    it 'shows the other team messages to the exempt agent' do
      create(:inbox_isolation_exemption, inbox: inbox, user: agent, isolation_type: 'team_message')
      Current.user = agent

      expect(visible_message_ids).to include(public_msg.id, from_team_a.id, from_team_b.id)
    end

    it 'keeps hiding them from an agent who is not on the exemption list' do
      create(:inbox_isolation_exemption, inbox: inbox, user: agent, isolation_type: 'team_message')
      Current.user = create(:user, account: account, role: :agent)

      expect(visible_message_ids).not_to include(from_team_b.id)
    end

    # exceção do isolamento POR AGENTE não vale para o de time (critério 5: independentes)
    it 'ignores an exemption of the agent isolation' do
      create(:inbox_isolation_exemption, inbox: inbox, user: agent, isolation_type: 'agent_message')
      Current.user = agent

      expect(visible_message_ids).not_to include(from_team_b.id)
    end

    # O cenário medido na verificação adversarial: `admin_ve_oculta=false` para qualquer
    # administrador, mas `promovido_ve_oculta=true` para o ex-agente que tinha exceção.
    # Ele virava o ÚNICO administrador a escapar do isolamento por time, e a linha sumia
    # da tela junto (a lista de participantes só mostra agentes), então ninguém conseguia
    # removê-la. A guarda vive na LEITURA (User#fetch_isolation_exempt_inbox_ids), por
    # isso a linha é gravada DEPOIS da promoção: assim o teste retrata a linha que já
    # estava no banco antes da correção, que é o caso que nenhum evento alcança.
    it 'keeps the filter for an agent promoted to administrator with an old exemption row' do
      account.account_users.find_by(user_id: agent.id).update!(role: :administrator)
      create(:inbox_isolation_exemption, inbox: inbox, user: agent, isolation_type: 'team_message')

      Current.user = User.find(agent.id)

      expect(visible_message_ids).not_to include(from_team_b.id)
      # e enxerga exatamente o que qualquer outro administrador enxerga
      Current.user = admin
      expect(visible_message_ids).not_to include(from_team_b.id)
    end

    # Complemento da guarda acima: a linha também é apagada no momento da promoção, para
    # não voltar a valer calada se a pessoa for despromovida depois.
    it 'drops the exemption when the agent becomes an administrator' do
      create(:inbox_isolation_exemption, inbox: inbox, user: agent, isolation_type: 'team_message')

      account.account_users.find_by(user_id: agent.id).update!(role: :administrator)

      expect(InboxIsolationExemption.where(user_id: agent.id)).to be_empty
      Current.user = User.find(agent.id)
      expect(visible_message_ids).not_to include(from_team_b.id)
    end

    it 'does not leak the exemption to another inbox' do
      other_inbox = create(:inbox, account: account, team_message_isolation: true)
      other_conversation = create(:conversation, account: account, inbox: other_inbox, team: team_a)
      hidden = create(:message, conversation: other_conversation, account: account, inbox: other_inbox, message_type: :outgoing)
      hidden.update_column(:team_id, team_b.id) # rubocop:disable Rails/SkipsModelValidations
      create(:inbox_isolation_exemption, inbox: inbox, user: agent, isolation_type: 'team_message')
      Current.user = agent

      expect(other_conversation.reload.messages.map(&:id)).not_to include(hidden.id)
    end
  end
end
