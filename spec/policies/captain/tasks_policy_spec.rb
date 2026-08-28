# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::TasksPolicy, type: :policy do
  subject(:tasks_policy) { described_class }

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:agent_context) { { user: agent, account: account, account_user: account.account_users.first } }

  # A sugestao de rotulos nunca teve gate: o metodo devolvia `true` fixo e o interruptor
  # da tela de Agentes IA nao fazia nada. Agora o interruptor manda, mas conta que nunca
  # mexeu nele continua com o recurso ligado.
  permissions :label_suggestion? do
    context 'when the account never touched the toggle' do
      it { expect(tasks_policy).to permit(agent_context, :'captain/tasks') }
    end

    context 'when the toggle was explicitly turned off' do
      before { account.update!(captain_features: { 'label_suggestion' => false }) }

      it { expect(tasks_policy).not_to permit(agent_context, :'captain/tasks') }
    end

    context 'when the toggle was explicitly turned on' do
      before { account.update!(captain_features: { 'label_suggestion' => true }) }

      it { expect(tasks_policy).to permit(agent_context, :'captain/tasks') }
    end

    context 'when another feature was saved and label_suggestion stayed absent' do
      before { account.update!(captain_features: { 'audio_transcription' => true }) }

      it { expect(tasks_policy).to permit(agent_context, :'captain/tasks') }
    end
  end

  permissions :rewrite?, :summarize?, :reply_suggestion?, :follow_up? do
    context 'when the label_suggestion toggle is off' do
      before { account.update!(captain_features: { 'label_suggestion' => false }) }

      it { expect(tasks_policy).to permit(agent_context, :'captain/tasks') }
    end
  end
end
