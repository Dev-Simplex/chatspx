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

  # pattr_initialize [:conversation!] exige a CHAVE, não rejeita nil: um episódio órfão
  # (conversa apagada, sem FK na tabela) entregava conversation: nil e estourava em #rows,
  # matando o eval da conta inteira. Sem conversa não há mensagens para segmentar.
  def perform
    return [] if conversation.nil?

    segments = build_segments
    persist(segments)
  end

  # Fronteiras EM MEMÓRIA, sem gravar nada. O runtime da IA precisa da fronteira NO INSTANTE
  # do turno, e o cron só passa depois — medido na conv 20215: cliente às 09:40:07, IA às
  # 09:41:55, episódios criados às 10:07:17. Quem depende da tabela fica sem fronteira
  # exatamente no primeiro turno da reentrada, que é onde o dano acontece.
  #
  # Mesmo cálculo do #perform, com uma diferença deliberada: aqui a resolução e o template
  # CORTAM o episódio. Ver #tipo?.
  def preview
    @tipo_pelo_rotulo = true
    build_segments
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
  # Activities entram só como marcadores de resolução; template conta como HSM.
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
        hsm: tipo?(type, 'template') || (attrs.is_a?(Hash) && attrs['template_params'].present?),
        resolucao: tipo?(type, 'activity') && content.to_s.match?(/resolvid|resolved/i)
      }
    end
  end

  # `pluck` de coluna enum devolve o RÓTULO ("activity"), não o inteiro. A comparação com o
  # inteiro nunca casa, e assim a resolução e o template não cortavam episódio: só o gap. Na
  # conv 22777 (conta 6) isso entregou à IA o atendimento resolvido na véspera (CHAT-180).
  #
  # O runtime (#preview) compara pelo rótulo. O cron do Eval (#perform) segue com a comparação
  # antiga DE PROPÓSITO: decisão do Paulo em 01/10/2026, para não re-segmentar os episódios já
  # julgados e não quebrar a comparação do Eval no tempo. As duas segmentações divergem.
  def tipo?(type, rotulo)
    @tipo_pelo_rotulo ? type.to_s == rotulo : type == Message.message_types[rotulo]
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
      next if tipo?(row[:type], 'activity') # outras activities não são conversacionais

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

      if current && row[:hsm] && !tipo?(row[:type], 'incoming')
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
  def finalize(_segments, current, pending_close)
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
