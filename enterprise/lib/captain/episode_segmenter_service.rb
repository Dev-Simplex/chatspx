# Segmenta a conversa perpétua em EPISÓDIOS de atendimento (Eval 2.0 F1).
# Fronteiras determinísticas, em ordem de precedência:
#   1. resolve→reopen (activity de resolução do Chatwoot) — fronteira dura;
#      reply do cliente < REOPEN_GRACE após o resolve reabre o MESMO episódio
#      (resolve prematuro não é atendimento novo).
#   2. HSM outbound de campanha/follow-up (template_params) abre episódio novo —
#      o assunto muda por iniciativa do negócio.
#   3. Gap de inatividade >= gap da conta (default 24h, a janela nativa do WhatsApp).
# Idempotente e incremental: episódios fechados são imutáveis (mensagens passadas
# não mudam) — o serviço preserva os que continuam idênticos (match por
# first_message_id) e só ajusta/cria a cauda.
class Captain::EpisodeSegmenterService
  VERSION = 1
  REOPEN_GRACE = 1.hour
  DEFAULT_GAP_HOURS = 24

  Segment = Struct.new(:first_id, :last_id, :started_at, :last_at, :count, :reason, keyword_init: true)

  pattr_initialize [:conversation!]

  def perform
    segments = build_segments
    persist(segments)
  end

  private

  def account
    @account ||= conversation.account
  end

  def gap
    hours = account.custom_attributes&.dig('eval_episode_gap_hours').to_i
    (hours.positive? ? hours : DEFAULT_GAP_HOURS).hours
  end

  # [id, message_type, created_at, hsm?, resolucao?] em ordem cronológica.
  # Activities entram só como marcadores de resolução; template (3) conta como HSM.
  def rows
    @rows ||= conversation.messages
                          .where(message_type: %i[incoming outgoing activity template])
                          .where(private: false)
                          .reorder(:created_at, :id)
                          .pluck(:id, :message_type, :created_at, :additional_attributes,
                                 Arel.sql('LEFT(content, 120)'))
                          .map do |id, type, at, attrs, content|
      {
        id: id,
        type: type,
        at: at,
        hsm: type == 3 || (attrs.is_a?(Hash) && attrs['template_params'].present?),
        resolucao: type == 2 && content.to_s.match?(/resolvid|resolved/i)
      }
    end
  end

  def build_segments
    segments = []
    current = nil
    pending_close = nil

    rows.each do |row|
      if row[:resolucao]
        pending_close = row[:at] if current
        next
      end
      next if row[:type] == 2 # outras activities não são conversacionais

      if current && pending_close
        if row[:at] - pending_close < REOPEN_GRACE
          # dentro da graça pós-resolve: resolve prematuro ou cauda do encerramento
          # (pesquisa NPS, agradecimento) — pertence ao MESMO episódio
          pending_close = nil
        else
          current.reason = 'resolve'
          current = close_and_open(segments, current, row)
          pending_close = nil
          next
        end
      end

      if current && row[:at] - current.last_at >= gap
        current.reason = 'gap'
        current = close_and_open(segments, current, row)
        next
      end

      if current && row[:hsm] && row[:type] != 0
        current.reason = 'hsm_campanha'
        current = close_and_open(segments, current, row)
        next
      end

      current = append(segments, current, row)
    end

    finalize(segments, current, pending_close)
    segments
  end

  def append(segments, current, row)
    if current.nil?
      current = Segment.new(first_id: row[:id], last_id: row[:id], started_at: row[:at],
                            last_at: row[:at], count: 1, reason: 'aberto')
      segments << current
    else
      current.last_id = row[:id]
      current.last_at = row[:at]
      current.count += 1
    end
    current
  end

  def close_and_open(segments, _closed, row)
    fresh = Segment.new(first_id: row[:id], last_id: row[:id], started_at: row[:at],
                        last_at: row[:at], count: 1, reason: 'aberto')
    segments << fresh
    fresh
  end

  # O último segmento fecha se: houve resolve pendente sem reply, a conversa está
  # resolvida, ou o gap já venceu. Senão permanece aberto (ended_at nil).
  def finalize(segments, current, pending_close)
    return if current.nil?

    if pending_close
      current.reason = 'resolve'
    elsif conversation.resolved?
      current.reason = 'resolve'
    elsif Time.current - current.last_at >= gap
      current.reason = 'gap'
    end
  end

  def persist(segments)
    existing = Captain::ConversationEpisode.where(conversation_id: conversation.id).index_by(&:first_message_id)
    kept_firsts = []

    records = segments.each_with_index.map do |seg, index|
      kept_firsts << seg.first_id
      record = existing[seg.first_id] || Captain::ConversationEpisode.new(
        account_id: account.id, conversation_id: conversation.id, first_message_id: seg.first_id
      )
      record.assign_attributes(
        seq: index + 1,
        last_message_id: seg.last_id,
        started_at: seg.started_at,
        last_message_at: seg.last_at,
        ended_at: seg.reason == 'aberto' ? nil : seg.last_at,
        boundary_reason: seg.reason,
        mensagens: seg.count,
        segmenter_version: VERSION
      )
      record
    end

    Captain::ConversationEpisode.transaction do
      # remove episódios cuja fronteira inicial não existe mais (mudança de regra/versão)
      Captain::ConversationEpisode.where(conversation_id: conversation.id)
                                  .where.not(first_message_id: kept_firsts)
                                  .destroy_all
      # renumeração em 2 fases: registros existentes que trocam de seq passam por um
      # valor temporário negativo, evitando colisão transitória no unique (conv, seq)
      renumbered = records.select { |r| r.persisted? && r.seq_changed? }
      renumbered.each_with_index { |r, i| Captain::ConversationEpisode.where(id: r.id).update_all(seq: -(i + 1)) }
      records.each { |record| record.save! if record.changed? || record.seq_changed? }
    end

    records
  end
end
