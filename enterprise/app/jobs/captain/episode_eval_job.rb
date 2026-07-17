# Avalia UM episódio fechado e faz upsert do veredito (Eval 2.0 F1). Idempotente:
# episódios fechados são imutáveis, então cada um é julgado uma única vez (re-julga
# só se a faixa de mensagens mudou — re-segmentação).
class Captain::EpisodeEvalJob < ApplicationJob
  queue_as :low

  def perform(episode)
    return if episode.ended_at.blank?

    conversation = episode.conversation
    account = conversation.account
    return unless Captain::ConversationEval.enabled_for?(account)

    existing = Captain::ConversationEval.find_by(episode_id: episode.id)
    return if existing && existing.mensagens_avaliadas == episode.mensagens

    result = Captain::ConversationEvalService.new(
      account: account,
      conversation_display_id: conversation.display_id,
      episode: episode
    ).perform
    return if result[:error].present? || result[:verdict].blank?

    verdict = merge_gate_findings(episode, result[:verdict])
    persist(episode, conversation, account, verdict, existing)
  end

  private

  # Flagras objetivos do gate determinístico (custo zero) entram junto dos findings
  # do juiz, marcados com origem 'gate'. Falha do gate nunca derruba o eval.
  def merge_gate_findings(episode, verdict)
    gate = Captain::EpisodeGateService.new(episode: episode).perform
    return verdict if gate.empty?

    verdict.merge(response_findings: gate + Array(verdict[:response_findings]))
  rescue StandardError => e
    Rails.logger.warn("[eval-gate] falhou no episódio #{episode.id}: #{e.class} #{e.message}")
    verdict
  end

  def persist(episode, conversation, account, verdict, existing)
    record = existing || Captain::ConversationEval.new(conversation_id: conversation.id, episode_id: episode.id)
    record.assign_attributes(
      account_id: account.id,
      captain_assistant_id: assistant_id_for(conversation, episode),
      mensagens_avaliadas: episode.mensagens,
      avaliado_em: Time.now.utc,
      **verdict
    )
    record.save!
  end

  # Assistente dominante DO EPISÓDIO (não da conversa): o último que respondeu
  # dentro da faixa de mensagens do episódio.
  def assistant_id_for(conversation, episode)
    conversation.messages
                .where(id: episode.first_message_id..episode.last_message_id)
                .where(sender_type: 'Captain::Assistant')
                .reorder(:created_at).last&.sender_id ||
      conversation.assignee_agent_bot&.captain_assistant&.id
  end
end
