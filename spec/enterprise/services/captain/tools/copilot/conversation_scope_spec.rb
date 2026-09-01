require 'rails_helper'

# Quem escolhe o `conversation_id` é o MODELO. Os tools escopavam por `account.conversations`,
# o que fecha a fronteira de CONTA mas não a de ACESSO: dentro da mesma conta o app tem um
# segundo limite (Conversations::PermissionFilterService, o mesmo do ConversationFinder e do
# `authorize_team_access` que devolve 403 na tela) e pelo copilot ele não existia.
#
# Dois perfis de ator, porque os tools se dividem assim na prática:
#   - LEITURA: papel restrito (`conversation_participating_manage`) — o `active?` desses tools
#     admite esse papel de propósito, e era justamente para ele que a leitura vinha sem limite.
#   - ESCRITA: agente simples sem custom role — o `user_has_permission` devolve true para
#     qualquer permissão nesse caso, então ele recebe todos os tools de escrita.
RSpec.describe Captain::Tools::Copilot::ConversationScope do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }

  let(:own_inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }

  # Conversa de outra caixa: existe na conta, mas fora do alcance do ator.
  let(:conversation) { create(:conversation, account: account, inbox: other_inbox) }

  let(:refusal) { "Conversation ##{conversation.display_id} is outside your access scope in this account" }

  describe 'read tools' do
    let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_participating_manage']) }
    let(:broker) { create(:user, account: account) }

    before do
      AccountUser.find_by(user: broker, account: account).update!(role: :agent, custom_role: custom_role)
      create(:inbox_member, user: broker, inbox: own_inbox)
    end

    it 'get_conversation refuses a conversation assigned to someone else' do
      service = Captain::Tools::Copilot::GetConversationService.new(assistant, user: broker)

      expect(service.execute(conversation_id: conversation.display_id)).to eq(refusal)
    end

    it 'get_conversation does not leak private notes of a conversation out of reach' do
      create(:message, conversation: conversation, message_type: 'outgoing', content: 'segredo do outro corretor', private: true)
      service = Captain::Tools::Copilot::GetConversationService.new(assistant, user: broker)

      expect(service.execute(conversation_id: conversation.display_id)).not_to include('segredo do outro corretor')
    end

    it 'get_conversation_full refuses a conversation assigned to someone else' do
      service = Captain::Tools::Copilot::GetConversationFullService.new(assistant, user: broker)

      expect(service.execute(conversation_id: conversation.display_id)).to eq(refusal)
    end

    it 'get_conversation still serves a conversation assigned to the broker' do
      mine = create(:conversation, account: account, inbox: own_inbox, assignee: broker)
      service = Captain::Tools::Copilot::GetConversationService.new(assistant, user: broker)

      expect(service.execute(conversation_id: mine.display_id)).to eq(mine.to_llm_text)
    end

    # Recusa distingue "não existe" de "existe e você não alcança" — recusa sem motivo é
    # indistinguível de alucinação do modelo (mesmo critério do #43).
    it 'keeps the plain not-found message for an id that does not exist' do
      service = Captain::Tools::Copilot::GetConversationService.new(assistant, user: broker)

      expect(service.execute(conversation_id: 0)).to eq('Conversation not found')
    end
  end

  describe 'write tools' do
    # Agente simples: não é membro da caixa em que a conversa vive.
    let(:agent) { create(:user, account: account) }

    before { create(:inbox_member, user: agent, inbox: own_inbox) }

    def tool(klass)
      klass.new(assistant, user: agent)
    end

    it 'send_message refuses and sends nothing' do
      service = tool(Captain::Tools::Copilot::SendMessageService)
      result = nil

      expect { result = service.execute(conversation_id: conversation.display_id, content: 'oi') }
        .not_to change(Message, :count)
      expect(result).to eq(refusal)
    end

    it 'send_template refuses and sends nothing' do
      service = tool(Captain::Tools::Copilot::SendTemplateService)
      result = nil

      expect { result = service.execute(conversation_id: conversation.display_id, template_name: 'promo') }
        .not_to change(Message, :count)
      expect(result).to eq(refusal)
    end

    it 'resolve_conversation refuses and leaves the status untouched' do
      expect(tool(Captain::Tools::Copilot::ResolveConversationService)
        .execute(conversation_id: conversation.display_id)).to eq(refusal)
      expect(conversation.reload).not_to be_resolved
    end

    it 'snooze_conversation refuses and leaves the status untouched' do
      expect(tool(Captain::Tools::Copilot::SnoozeConversationService)
        .execute(conversation_id: conversation.display_id, hours: 4)).to eq(refusal)
      expect(conversation.reload.snoozed_until).to be_nil
    end

    it 'change_status refuses and leaves the status untouched' do
      expect(tool(Captain::Tools::Copilot::ChangeStatusService)
        .execute(conversation_id: conversation.display_id, status: 'resolved')).to eq(refusal)
      expect(conversation.reload).not_to be_resolved
    end

    it 'change_priority refuses and leaves the priority untouched' do
      expect(tool(Captain::Tools::Copilot::ChangePriorityService)
        .execute(conversation_id: conversation.display_id, priority: 'urgent')).to eq(refusal)
      expect(conversation.reload.priority).to be_nil
    end

    it 'add_label refuses and applies no label' do
      expect(tool(Captain::Tools::Copilot::AddLabelService)
        .execute(conversation_id: conversation.display_id, label: 'vip')).to eq(refusal)
      expect(conversation.reload.label_list).to be_empty
    end

    it 'remove_label refuses and keeps the existing labels' do
      conversation.update!(label_list: ['vip'])

      expect(tool(Captain::Tools::Copilot::RemoveLabelService)
        .execute(conversation_id: conversation.display_id, label: 'vip')).to eq(refusal)
      expect(conversation.reload.label_list).to include('vip')
    end

    it 'set_custom_attributes refuses and writes nothing' do
      expect(tool(Captain::Tools::Copilot::SetCustomAttributesService)
        .execute(target_type: 'conversation', target_id: conversation.display_id,
                 attributes: '{"origem":"copilot"}')).to eq(refusal)
      expect(conversation.reload.custom_attributes).to be_blank
    end

    it 'transfer_to_inbox refuses and leaves the conversation in its inbox' do
      expect(tool(Captain::Tools::Copilot::TransferToInboxService)
        .execute(conversation_id: conversation.display_id, inbox_id: own_inbox.id)).to eq(refusal)
      expect(conversation.reload.inbox_id).to eq(other_inbox.id)
    end

    it 'still writes on a conversation inside the reach' do
      mine = create(:conversation, account: account, inbox: own_inbox)

      expect(tool(Captain::Tools::Copilot::ChangePriorityService)
        .execute(conversation_id: mine.display_id, priority: 'urgent'))
        .to eq("Conversation ##{mine.display_id} priority changed to urgent")
      expect(mine.reload.priority).to eq('urgent')
    end
  end

  # Gestor não perde nada: o PermissionFilterService devolve o escopo cru para administrador.
  describe 'administrators' do
    let(:admin) { create(:user, :administrator, account: account) }

    it 'reads any conversation of the account' do
      service = Captain::Tools::Copilot::GetConversationService.new(assistant, user: admin)

      expect(service.execute(conversation_id: conversation.display_id)).to eq(conversation.to_llm_text)
    end

    it 'writes on any conversation of the account' do
      Captain::Tools::Copilot::ResolveConversationService
        .new(assistant, user: admin)
        .execute(conversation_id: conversation.display_id)

      expect(conversation.reload).to be_resolved
    end
  end

  # A fronteira de conta continua fechada, e continua respondendo "não existe".
  describe 'account boundary' do
    let(:admin) { create(:user, :administrator, account: account) }
    let(:foreign_conversation) { create(:conversation, account: create(:account)) }

    it 'refuses a conversation of another account as not found' do
      service = Captain::Tools::Copilot::GetConversationService.new(assistant, user: admin)

      expect(service.execute(conversation_id: foreign_conversation.display_id)).to eq('Conversation not found')
    end
  end
end
