class CaptainListener < BaseListener
  include ::Events::Types

  def conversation_resolved(event)
    conversation = extract_conversation_and_account(event)[0]
    assistant = assistant_for(conversation)
    return unless assistant
    return unless conversation.inbox.captain_active?

    Captain::Llm::ContactNotesService.new(assistant, conversation).generate_and_update_notes if assistant.config['feature_memory'].present?
    Captain::Llm::ConversationFaqService.new(assistant, conversation).generate_and_deduplicate if assistant.config['feature_faq'].present?
  end

  # F4.2 (Eval humano): nota privada de gestor com o marcador #eval é um veredito
  # humano sobre o atendimento — re-julga o episódio correspondente na hora, com a
  # anotação no prompt do juiz (peso máximo) e escalação pro modelo forte.
  # Episódio ainda aberto não precisa de ação: o julgamento normal ao fechar já lê
  # as anotações via ConversationEpisode#human_annotations.
  def message_created(event)
    message, account = extract_message_and_account(event)
    return unless message.private? && message.sender_type == 'User'
    return unless message.content.to_s.match?(/#eval\b/i)
    return unless Captain::ConversationEval.enabled_for?(account)

    episode = annotation_target_episode(message)
    return if episode.nil? || episode.ended_at.blank?

    Captain::EpisodeEvalJob.perform_later(episode, force: true)
  rescue StandardError => e
    Rails.logger.error("[CaptainListener] eval annotation conv=#{message&.conversation_id}: #{e.message}")
  end

  private

  # Âncora EXPLÍCITA do modal "Avaliar atendimento" (eval_episode_id) tem prioridade;
  # nota #eval solta cai na heurística temporal (último episódio iniciado antes dela).
  def annotation_target_episode(message)
    explicit_id = message.content_attributes&.dig('eval_episode_id')
    if explicit_id.present?
      return Captain::ConversationEpisode.find_by(id: explicit_id, conversation_id: message.conversation_id)
    end

    Captain::ConversationEpisode.where(conversation_id: message.conversation_id)
                                .where(started_at: ..message.created_at)
                                .order(:seq).last
  end

  # Dono atual (espelho) ou, pós-handoff (bot já desatribuído por A2e), o participante:
  # última mensagem com sender Captain::Assistant.
  def assistant_for(conversation)
    conversation.assignee_agent_bot&.captain_assistant ||
      conversation.messages.where(sender_type: 'Captain::Assistant').order(:created_at).last&.sender
  end
end
