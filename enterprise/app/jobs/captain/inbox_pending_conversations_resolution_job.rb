class Captain::InboxPendingConversationsResolutionJob < ApplicationJob
  CAPTAIN_INFERENCE_RESOLVE_ACTIVITY_REASON = 'no outstanding questions'.freeze
  CAPTAIN_INFERENCE_HANDOFF_ACTIVITY_REASON = 'pending clarification from customer'.freeze

  queue_as :low

  def perform(inbox)
    return if inbox.account.captain_auto_resolve_disabled?

    if evaluate_conversation_completion?(inbox.account)
      perform_with_evaluation(inbox)
    else
      perform_time_based(inbox)
    end
  ensure
    Current.reset
  end

  private

  def evaluate_conversation_completion?(account)
    account.feature_enabled?('captain_tasks') && account.captain_auto_resolve_evaluated?
  end

  def perform_time_based(inbox)
    resolvable_pending_conversations(inbox).each do |conversation|
      assistant = assistant_for(conversation)
      next if assistant.blank?

      Current.executed_by = assistant
      create_resolution_message(conversation, assistant)
      conversation.resolved!
    end
  end

  def perform_with_evaluation(inbox)
    resolvable_pending_conversations(inbox).each do |conversation|
      assistant = assistant_for(conversation)
      next if assistant.blank?

      Current.executed_by = assistant
      evaluation = evaluate_conversation(conversation, inbox)
      next unless still_resolvable_after_evaluation?(conversation)

      if evaluation[:complete]
        resolve_conversation(conversation, assistant, evaluation[:reason])
      else
        handoff_conversation(conversation, assistant, evaluation[:reason])
      end
    end
  end

  # Resolve o assistant pela CONVERSA (dono atual -> participante -> elegível da inbox como
  # rede de segurança do legado, A9.4 — desvio CONSCIENTE de D-6 documentado no design).
  def assistant_for(conversation)
    conversation.assignee_agent_bot&.captain_assistant ||
      conversation.messages.where(sender_type: 'Captain::Assistant').order(:created_at).last&.sender ||
      conversation.inbox.captain_assistants.first
  end

  def evaluate_conversation(conversation, inbox)
    Captain::ConversationCompletionService.new(
      account: inbox.account,
      conversation_display_id: conversation.display_id
    ).perform
  end

  def resolvable_pending_conversations(inbox)
    inbox.conversations.pending
         .where('last_activity_at < ?', auto_resolve_cutoff_time)
         .limit(Limits::BULK_ACTIONS_LIMIT)
  end

  def still_resolvable_after_evaluation?(conversation)
    conversation.reload
    conversation.pending? && conversation.last_activity_at < auto_resolve_cutoff_time
  rescue ActiveRecord::RecordNotFound
    false
  end

  def auto_resolve_cutoff_time
    Time.now.utc - 1.hour
  end

  def resolve_conversation(conversation, assistant, reason)
    create_private_note(conversation, assistant, "Auto-resolved: #{reason}")
    create_resolution_message(conversation, assistant)
    conversation.with_captain_activity_context(
      reason: CAPTAIN_INFERENCE_RESOLVE_ACTIVITY_REASON,
      reason_type: :inference
    ) { conversation.resolved! }
    conversation.dispatch_captain_inference_resolved_event
  end

  def handoff_conversation(conversation, assistant, reason)
    create_private_note(conversation, assistant, "Auto-handoff: #{reason}")
    create_handoff_message(conversation, assistant)
    conversation.with_captain_activity_context(
      reason: CAPTAIN_INFERENCE_HANDOFF_ACTIVITY_REASON,
      reason_type: :inference
    ) { conversation.bot_handoff! }
    conversation.dispatch_captain_inference_handoff_event
    send_out_of_office_message_if_applicable(conversation.reload)
  end

  def send_out_of_office_message_if_applicable(conversation)
    # Campaign conversations should never receive OOO templates — the campaign itself
    # serves as the initial outreach, and OOO would be confusing in that context.
    return if conversation.campaign.present?

    ::MessageTemplates::Template::OutOfOffice.perform_if_applicable(conversation)
  end

  def create_private_note(conversation, assistant, content)
    conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      sender: assistant,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      content: content
    )
  end

  def create_resolution_message(conversation, assistant)
    I18n.with_locale(conversation.account.locale) do
      resolution_message = assistant.config['resolution_message']
      conversation.messages.create!(
        message_type: :outgoing,
        account_id: conversation.account_id,
        inbox_id: conversation.inbox_id,
        content: resolution_message.presence || I18n.t('conversations.activity.auto_resolution_message'),
        sender: assistant
      )
    end
  end

  def create_handoff_message(conversation, assistant)
    handoff_message = assistant.config['handoff_message']
    return if handoff_message.blank?

    conversation.messages.create!(
      message_type: :outgoing,
      sender: assistant,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      content: handoff_message,
      preserve_waiting_since: true
    )
  end
end
