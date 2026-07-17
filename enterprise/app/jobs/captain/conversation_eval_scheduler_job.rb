# Batch horário do eval. Varre as contas com o gate ligado e enfileira a avaliação.
# Unidade por conta (custom_attributes['eval_unit']):
#   - 'episode' (Eval 2.0): segmenta as conversas tocadas em episódios, fecha os
#     vencidos e julga SÓ episódios fechados ainda não avaliados — um julgamento
#     por atendimento, nunca o blob da conversa.
#   - default (legado): julga por conversa; o ConversationEvalJob decide idempotência.
# NO-OP em contas sem custom_attributes['eval_enabled'].
class Captain::ConversationEvalSchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  ELIGIBILITY_WINDOW = 25.hours
  MAX_PER_ACCOUNT = 200
  MAX_STALE_RESEGMENTS = 100
  # O cron julga o FLUXO (episódios que fecharam há pouco), nunca o backlog histórico —
  # backfill de histórico é decisão manual de custo (spx:eval:run_episodes). Mesma
  # janela de 7 dias do avaliador multi-turn do LangSmith.
  EPISODE_RECENT_WINDOW = 7.days

  def perform
    Account.find_each(batch_size: 100) do |account|
      next unless Captain::ConversationEval.enabled_for?(account)

      if Captain::ConversationEval.episode_unit?(account)
        enqueue_episodes_for_account(account)
      else
        enqueue_for_account(account)
      end
    end
  end

  private

  def captain_inbox_ids(account)
    CaptainInbox.where(inbox_id: account.inboxes.select(:id)).distinct.pluck(:inbox_id)
  end

  # ── unidade legado: por conversa ──────────────────────────────────────────
  def enqueue_for_account(account)
    inbox_ids = captain_inbox_ids(account)
    return if inbox_ids.empty?

    account.conversations
           .where(inbox_id: inbox_ids)
           .where('last_activity_at >= ?', ELIGIBILITY_WINDOW.ago)
           .order(last_activity_at: :desc)
           .limit(MAX_PER_ACCOUNT)
           .each { |conversation| Captain::ConversationEvalJob.perform_later(conversation) }
  end

  # ── unidade Eval 2.0: por episódio ────────────────────────────────────────
  def enqueue_episodes_for_account(account)
    inbox_ids = captain_inbox_ids(account)
    return if inbox_ids.empty?

    segment_touched_conversations(account, inbox_ids)
    resegment_stale_open_episodes(account)
    enqueue_closed_episodes(account)
  end

  def segment_touched_conversations(account, inbox_ids)
    account.conversations
           .where(inbox_id: inbox_ids)
           .where('last_activity_at >= ?', ELIGIBILITY_WINDOW.ago)
           .order(last_activity_at: :desc)
           .limit(MAX_PER_ACCOUNT)
           .each { |conversation| Captain::EpisodeSegmenterService.new(conversation: conversation).perform }
  end

  # Episódios abertos cuja última mensagem já venceu o gap fecham por decurso —
  # mesmo sem atividade nova na conversa (a conversa saiu da janela de varredura).
  def resegment_stale_open_episodes(account)
    gap_hours = account.custom_attributes&.dig('eval_episode_gap_hours').to_i
    gap_hours = Captain::EpisodeSegmenterService::DEFAULT_GAP_HOURS unless gap_hours.positive?

    Captain::ConversationEpisode.open_ones
                                .for_account(account.id)
                                .where('last_message_at < ?', gap_hours.hours.ago)
                                .order(last_message_at: :asc)
                                .limit(MAX_STALE_RESEGMENTS)
                                .includes(:conversation)
                                .each { |ep| Captain::EpisodeSegmenterService.new(conversation: ep.conversation).perform }
  end

  def enqueue_closed_episodes(account)
    judged = Captain::ConversationEval.for_account(account.id).por_episodio.select(:episode_id)
    Captain::ConversationEpisode.closed
                                .for_account(account.id)
                                .where('ended_at >= ?', EPISODE_RECENT_WINDOW.ago)
                                .where.not(id: judged)
                                .order(ended_at: :desc)
                                .limit(MAX_PER_ACCOUNT)
                                .each { |episode| Captain::EpisodeEvalJob.perform_later(episode) }
  end
end
