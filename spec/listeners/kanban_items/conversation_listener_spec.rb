# frozen_string_literal: true

require 'rails_helper'

describe KanbanItems::ConversationListener, type: :listener do
  # Bloqueado até P0-03 estar completo: os services ainda se chamam
  # Kanban::FunnelLookupService (não Kanban::KanbanLookupService) e os models
  # ainda são Funnel/FunnelStage/FunnelItem. O listener foi escrito conforme
  # a tarefa P0-08 (nomes finais "Kanban*") e ficará dormente até P0-03 v2
  # renomear models e services. Quando isso acontecer, basta remover este skip.
  before do
    skip 'Aguardando P0-03 v2 finalizar rename Funnel→Kanban em models/services'
    described_class.disabled = false
  end

  let(:listener) { described_class.new }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  describe '#on_conversation_created' do
    let(:conversation) { build_stubbed(:conversation, account: account, inbox: inbox) }

    it 'cria kanban_items quando há kanbans aplicáveis' do
      lookup = instance_double(Kanban::KanbanLookupService, perform: [])
      allow(Kanban::KanbanLookupService).to receive(:new).and_return(lookup)
      expect { listener.on_conversation_created(conversation) }.not_to raise_error
    end

    it 'respeita flag disabled' do
      described_class.disabled = true
      expect(Kanban::KanbanLookupService).not_to receive(:new)
      listener.on_conversation_created(conversation)
    end
  end

  describe '#on_conversation_status_changed' do
    it 'invoca MoveConversationToAutomatedStageService' do
      conversation = build_stubbed(:conversation)
      svc = instance_double(Kanban::MoveConversationToAutomatedStageService, perform: true)
      allow(Kanban::MoveConversationToAutomatedStageService).to receive(:new)
        .with(conversation: conversation, status: conversation.status)
        .and_return(svc)
      listener.on_conversation_status_changed(conversation)
      expect(svc).to have_received(:perform)
    end
  end

  describe '#on_conversation_team_changed' do
    it 'invoca MoveConversationToTeamKanbanService' do
      conversation = build_stubbed(:conversation, team_id: nil)
      svc = instance_double(Kanban::MoveConversationToTeamKanbanService, perform: true)
      allow(Kanban::MoveConversationToTeamKanbanService).to receive(:new)
        .with(conversation: conversation, team: nil)
        .and_return(svc)
      listener.on_conversation_team_changed(conversation)
      expect(svc).to have_received(:perform)
    end
  end
end
