# Reconciliação (22 §1.5): o estado das conversas dos leads, para o Captador recuperar o que um
# evento perdido não trouxe (as retentativas do WebhookJob acabam em cerca de 6 minutos).
#
# Casa pelo lead gravado na conversa (custom_attributes.captador_lead_id) e pelo contato: quando o
# lead volta a escrever depois de a conversa ser resolvida, nasce uma conversa nova sem o carimbo,
# no mesmo contato. `since` devolve só o que mudou desde o instante: a conversa, o seu último
# movimento ou qualquer mensagem dela (status de entrega muda a mensagem, não a conversa).
class Spx::Captador::ConversasController < Spx::Captador::BaseController
  MAX_IDS = 100
  MAX_CONVERSATIONS = 500
  CHANGED_SINCE = <<~SQL.squish.freeze
    conversations.updated_at >= :since OR conversations.last_activity_at >= :since OR EXISTS (
      SELECT 1 FROM messages WHERE messages.conversation_id = conversations.id AND messages.updated_at >= :since
    )
  SQL

  def index
    return render_error(:unprocessable_entity, 'ids_required') if lead_ids.empty? && contact_ids.empty?
    return render_error(:unprocessable_entity, 'too_many_ids') if lead_ids.size + contact_ids.size > MAX_IDS
    return render_error(:unprocessable_entity, 'invalid_since') if params[:since].present? && since.nil?

    server_time = Time.current
    conversations = matching_conversations.to_a
    render json: { server_time: server_time.iso8601(3), conversations: conversations_json(conversations) }
  end

  private

  def lead_ids
    @lead_ids ||= params[:lead_ids].to_s.split(',').map(&:strip).compact_blank.uniq
  end

  def contact_ids
    @contact_ids ||= params[:contact_ids].to_s.split(',').map(&:strip).grep(/\A\d+\z/).map(&:to_i).uniq
  end

  # ISO 8601 ou epoch em segundos.
  def since
    @since ||= params[:since].to_s.match?(/\A\d+\z/) ? Time.zone.at(params[:since].to_i) : Time.zone.iso8601(params[:since].to_s)
  rescue ArgumentError
    nil
  end

  def matching_conversations
    by_lead = @account.conversations.where("conversations.custom_attributes ->> 'captador_lead_id' IN (?)", lead_ids.presence || [''])
    scope = by_lead.or(@account.conversations.where(contact_id: contact_ids))
    scope = scope.where(CHANGED_SINCE, since: since) if params[:since].present?
    scope.includes(:contact, :assignee, :team).order(:id).limit(MAX_CONVERSATIONS)
  end

  def conversations_json(conversations)
    ids = conversations.map(&:id)
    # reorder(nil): o default_scope do Message ordena por created_at, e ORDER BY fora do GROUP BY quebra no Postgres.
    last_incoming = Message.where(conversation_id: ids).incoming.reorder(nil).group(:conversation_id).maximum(:created_at)
    opened_by_captador = Message.where(conversation_id: ids).where("additional_attributes ->> 'echo_id' LIKE 'captador:%'")
                                .order(:created_at).index_by(&:conversation_id)
    opted_out = ContactFlowSuppression.active.where(contact_id: conversations.map(&:contact_id), category: %w[marketing all])
                                      .distinct.pluck(:contact_id).to_set

    conversations.map do |conversation|
      conversation_json(conversation, last_incoming[conversation.id], opened_by_captador[conversation.id])
        .merge(opt_out: opted_out.include?(conversation.contact_id))
    end
  end

  def conversation_json(conversation, last_incoming_at, captador_message)
    {
      conversation_id: conversation.display_id, contact_id: conversation.contact_id, inbox_id: conversation.inbox_id,
      lead_id: lead_id_of(conversation), status: conversation.status,
      assignee: conversation.assignee && { id: conversation.assignee.id, name: conversation.assignee.available_name },
      team: conversation.team && { id: conversation.team.id, name: conversation.team.name },
      last_activity_at: conversation.last_activity_at, last_incoming_at: last_incoming_at,
      captador_message: captador_message && message_json(captador_message)
    }
  end

  def lead_id_of(conversation)
    conversation.custom_attributes&.dig('captador_lead_id') || conversation.contact.custom_attributes&.dig('captador_lead_id')
  end

  def message_json(message)
    {
      id: message.id, status: message.status, created_at: message.created_at,
      external_error: message.content_attributes.try(:[], 'external_error')
    }
  end
end
