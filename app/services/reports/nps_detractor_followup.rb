# frozen_string_literal: true

# Metrica de "closing the loop" com detratores: quanto tempo se leva, em media,
# para um agente humano responder um detrator (0-6) depois que ele deu a nota,
# e quantos detratores ainda estao aguardando follow-up.
#
# Follow-up = primeira mensagem OUTGOING de agente (nao a propria pesquisa/thank-you
# de NPS, nao atividade) enviada na conversa DEPOIS que o detrator respondeu
# (answered_at). Se nao existe -> aguardando.
#
# Puramente derivado das mensagens (sem coluna nova). O coorte de detratores por
# periodo costuma ser pequeno; ainda assim limitamos o scan por seguranca.
class Reports::NpsDetractorFollowup
  SCAN_LIMIT = 500

  # detractor_scope: relation JA escopada (respondidas + detratoras + trusted + coorte do periodo).
  def initialize(detractor_scope)
    @detractor_scope = detractor_scope
  end

  def to_h
    stats = scan_detractors
    durations = stats[:durations]
    {
      total: durations.size + stats[:awaiting],
      followed_up_count: durations.size,
      awaiting_count: stats[:awaiting],
      avg_followup_seconds: average(durations),
      scan_truncated: stats[:truncated]
    }
  end

  private

  def scan_detractors
    durations = []
    awaiting = 0
    scanned = 0
    truncated = false

    detractors.find_each(batch_size: 100) do |nps|
      scanned += 1
      if scanned > SCAN_LIMIT
        truncated = true
        break
      end

      seconds = followup_seconds(nps)
      seconds ? durations << seconds : awaiting += 1
    end

    { durations: durations, awaiting: awaiting, truncated: truncated }
  end

  def average(durations)
    return nil if durations.empty?

    (durations.sum.to_f / durations.size).round
  end

  def detractors
    @detractor_scope.detractors.where.not(answered_at: nil)
  end

  # Segundos entre a resposta do detrator e a primeira resposta humana subsequente.
  #
  # O filtro roda em Ruby (nao em SQL) DE PROPOSITO: a coluna content_attributes e
  # um JSON serializado como STRING (duplo-encoded), entao `content_attributes ->> 'x'`
  # sempre devolve NULL. O accessor do modelo desserializa corretamente.
  def followup_seconds(nps)
    answered_at = nps.answered_at
    return nil if answered_at.blank?

    reply = nps.conversation.messages
               .where(message_type: :outgoing)
               .where('created_at >= ?', answered_at)
               .order(created_at: :asc)
               .limit(REPLY_SCAN_LIMIT)
               .find { |message| human_reply?(message) }
    return nil if reply.nil?

    (reply.created_at - answered_at).round
  end

  # So primeiras mensagens: a resposta humana costuma vir logo apos o agradecimento.
  REPLY_SCAN_LIMIT = 25

  # Ignora a propria pesquisa de NPS e o agradecimento automatico (skip_signature).
  def human_reply?(message)
    attrs = message.content_attributes || {}
    return false if truthy?(attrs['nps_survey'])
    return false if truthy?(attrs['skip_signature'])

    true
  end

  def truthy?(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end
end
