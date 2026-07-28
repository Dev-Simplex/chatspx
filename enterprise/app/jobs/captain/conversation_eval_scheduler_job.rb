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
    rescue StandardError => e
      # rede final: uma conta com dado inconsistente não pode impedir o eval das CONTAS
      # seguintes do find_each (era o efeito colateral mais grave do episódio órfão).
      report(e, account, "account=#{account.id}")
    end
  end

  private

  def report(error, account, context)
    Rails.logger.error("[ConversationEvalSchedulerJob] #{context} falhou: #{error.class}: #{error.message}")
    ChatwootExceptionTracker.new(error, account: account).capture_exception
  end

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
           .each do |conversation|
      Captain::EpisodeSegmenterService.new(conversation: conversation).perform
    rescue StandardError => e
      report(e, account, "conversation=#{conversation.id}")
    end
  end

  # Episódios abertos cuja última mensagem já venceu o gap fecham por decurso —
  # mesmo sem atividade nova na conversa (a conversa saiu da janela de varredura).
  def resegment_stale_open_episodes(account)
    gap_hours = account.custom_attributes&.dig('eval_episode_gap_hours').to_i
    gap_hours = Captain::EpisodeSegmenterService::DEFAULT_GAP_HOURS unless gap_hours.positive?

    # joins(:conversation): INNER JOIN descarta no SQL o episódio ÓRFÃO — conversa apagada
    # (não há FK nem dependent: na tabela), que entregava conversation: nil ao segmenter e
    # derrubava o eval da conta inteira. preload evita o N+1 que o includes dava de graça.
    Captain::ConversationEpisode.open_ones
                                .for_account(account.id)
                                .where('captain_conversation_episodes.last_message_at < ?', gap_hours.hours.ago)
                                .order(last_message_at: :asc)
                                .limit(MAX_STALE_RESEGMENTS)
                                .joins(:conversation)
                                .preload(:conversation)
                                .each do |ep|
      Captain::EpisodeSegmenterService.new(conversation: ep.conversation).perform
    rescue StandardError => e
      report(e, account, "episode=#{ep.id}")
    end
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
