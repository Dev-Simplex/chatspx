class MessageFinder
  def initialize(conversation, params)
    @conversation = conversation
    @params = params
  end

  def perform
    current_messages
  end

  private

  def conversation_messages
    base_query = @conversation.messages
      .for_team(@conversation.team_id)
      .where(inbox_id: @conversation.inbox_id)
      .includes(:attachments, :sender, sender: { avatar_attachment: [:blob] })
    
    # Adicionar reactions ao includes se a coluna existir
    if Message.column_names.include?('starred')
      base_query = base_query.includes(:reactions)
    end
    
    base_query
  end

  def messages
    base_messages = if @params[:filter_internal_messages].blank?
                      conversation_messages
                    else
                      conversation_messages.where.not('private = ? OR message_type = ?', true, 2)
                    end

    # Filtrar mensagens favoritas se solicitado
    if @params[:starred].present? && ActiveModel::Type::Boolean.new.cast(@params[:starred])
      if Message.column_names.include?('starred')
        base_messages = base_messages.where(starred: true)
      end
    end

    base_messages
  end

  def current_messages
    if @params[:after].present? && @params[:before].present?
      messages_between(@params[:after].to_i, @params[:before].to_i)
    elsif @params[:before].present?
      messages_before(@params[:before].to_i)
    elsif @params[:after].present?
      messages_after(@params[:after].to_i)
    else
      messages_latest
    end
  end

  def messages_after(after_id)
    messages.reorder('created_at asc').where('id > ?', after_id).limit(100)
  end

  def messages_before(before_id)
    messages.reorder('created_at desc').where('id < ?', before_id).limit(20).reverse
  end

  def messages_between(after_id, before_id)
    messages.reorder('created_at asc').where('id >= ? AND id < ?', after_id, before_id).limit(1000)
  end

  def messages_latest
    messages.reorder('created_at desc').limit(20).reverse
  end
end
