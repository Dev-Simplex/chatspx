require 'rails_helper'

# Quando a IA (Captain::Assistant) atribui agente/time, a atividade deve nomear a
# IA ("por Júlia") em vez do genérico "por Sistema de Automação".
RSpec.describe Enterprise::ActivityMessageHandler do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:team) { create(:team, account: account, name: 'locação') }
  let(:agent) { create(:user, account: account) }
  let(:assistant) { create(:captain_assistant, account: account, name: 'Júlia') }

  include ActiveJob::TestHelper

  after { Current.reset }

  context 'when a Captain::Assistant performs the assignment (Current.executed_by)' do
    it 'attributes a team change to the assistant name' do
      Current.executed_by = assistant

      expect do
        conversation.update!(team: team)
      end.to have_enqueued_job(Conversations::ActivityMessageJob).with(
        conversation.id,
        hash_including(message_type: :activity, content: "Assigned to #{team.name} by #{assistant.name}")
      )
    end

    it 'attributes an agent assignment to the assistant name' do
      Current.executed_by = assistant

      expect do
        conversation.update!(assignee: agent)
      end.to have_enqueued_job(Conversations::ActivityMessageJob).with(
        conversation.id,
        hash_including(message_type: :activity, content: "Assigned to #{agent.name} by #{assistant.name}")
      )
    end
  end

  context 'when an AutomationRule performs the assignment' do
    let(:rule) { create(:automation_rule, account: account) }

    it 'keeps the generic automation system attribution (super)' do
      Current.executed_by = rule

      expect do
        conversation.update!(team: team)
      end.to have_enqueued_job(Conversations::ActivityMessageJob).with(
        conversation.id,
        hash_including(message_type: :activity, content: "Assigned to #{team.name} by #{I18n.t('automation.system_name')}")
      )
    end
  end
end
