# Avisa o dono (pedido novo) e o solicitante (resposta).
#
# A Notification é criada DIRETO e SÍNCRONA, com secondary_actor explícito: o
# pedido não é efeito colateral de um evento, é o próprio ato. Isso também
# elimina o problema do Current.user nil no dispatcher assíncrono, em vez de
# contorná-lo.
#
# ⚠️ O SINO NÃO SERVE DE CTA: o RemoveDuplicateNotificationJob apaga por
# user_id + primary_actor_id IGNORANDO o tipo, então o aviso do pedido some na
# próxima mensagem da conversa. Por isso o pedido sobrevive na TABELA e a
# aprovação mora em superfícies duráveis (banner na conversa + lista "Pedidos").
# O sino só leva até a conversa.
class Conversations::TakeoverRequestNotifier
  def initialize(takeover_request)
    @request = takeover_request
  end

  def notify_requested
    return if @request.owner_id.blank?

    create_notification(
      user_id: @request.owner_id,
      type: :conversation_takeover_requested,
      actor: @request.requester
    )
    # nome pontilhado espelha FUNNEL_ITEM_MOVED ('funnel_item.moved') — o front
    # casa por string exata em helper/actionCable.js.
    broadcast('takeover_request.created', [@request.owner])
  end

  # Supersede: o pedido do PERDEDOR morreu porque um pedido irmão foi aprovado (ou
  # a conversa trocou de mãos por fora). Só broadcast, sem Notification (como o
  # cancel): o toaster do solicitante avisa e a aba/lista se refazem. Sem isto o
  # perdedor ficava preso em "Pedido enviado" até um refetch manual — justo o
  # cenário multi-agente que a feature existe para resolver.
  def notify_superseded
    broadcast('takeover_request.updated', [@request.requester].compact)
  end

  def notify_responded
    # Cancelar não notifica o dono: ruído puro (o solicitante desistiu).
    return broadcast('takeover_request.updated', [@request.owner].compact) if @request.cancelled?

    create_notification(
      user_id: @request.requester_id,
      type: :conversation_takeover_responded,
      actor: @request.responded_by
    )
    broadcast('takeover_request.updated', [@request.requester, @request.owner].compact.uniq)
  end

  private

  def create_notification(user_id:, type:, actor:)
    Notification.create!(
      account_id: @request.account_id,
      user_id: user_id,
      notification_type: type,
      primary_actor: @request.conversation,
      secondary_actor: actor
    )
  rescue StandardError => e
    # O aviso é acessório: se ele falhar, o PEDIDO (que é o que importa) não pode
    # cair junto — ele sobrevive na tabela e aparece no banner/lista.
    ChatwootExceptionTracker.new(e, account: @request.account).capture_exception
  end

  # Realtime DIRIGIDO: pedido é dado entre duas pessoas — nunca broadcast p/ a
  # conta inteira.
  def broadcast(event, users)
    tokens = users.compact.filter_map(&:pubsub_token)
    return if tokens.blank?

    ::ActionCableBroadcastJob.perform_later(tokens, event.to_s, payload)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @request.account).capture_exception
  end

  def payload
    {
      # account_id é OBRIGATÓRIO: o front descarta todo evento cujo data.account_id
      # não bate com a conta atual (isAValidEvent em actionCable.js). Sem ele o
      # realtime some silenciosamente — foi exatamente o que aconteceu.
      account_id: @request.account_id,
      id: @request.id,
      status: @request.status,
      conversation_id: @request.conversation.display_id,
      # nome do contato p/ o modal do dono ("Fulano quer a conversa com {contato}").
      contact: @request.conversation.contact && { name: @request.conversation.contact.name },
      requester: @request.requester && { id: @request.requester_id, name: @request.requester.available_name },
      owner_id: @request.owner_id,
      reason: @request.reason,
      # p/ o toast do solicitante quando negado/aprovado (a nota da resposta).
      response_note: @request.response_note
    }
  end
end
