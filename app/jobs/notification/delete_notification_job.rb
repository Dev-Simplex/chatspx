class Notification::DeleteNotificationJob < ApplicationJob
  queue_as :low

  # ChatSPX (C-21): o escopo por conta do upstream é correto e fica. A defensividade também: o
  # job recebe IDs, não objetos AR. Com objetos, o ActiveJob serializa por GlobalID e estoura
  # `ActiveJob::DeserializationError` se o usuário ou a conta forem apagados antes de o job rodar
  # — e este job existe justamente para rodar depois, na fila `low`.
  #
  # Duas correções aqui, ambas visíveis na fila e invisíveis na resposta HTTP (o controller só
  # enfileira e devolve 200):
  #
  # 1. a assinatura era `(user, account)` — DOIS posicionais, objetos — enquanto o
  #    NotificationsController chamava `perform_later(Current.user.id, type:)`, UM posicional.
  #    Todo "apagar notificações" estourava `ArgumentError` no worker;
  # 2. `type` era comparado como SÍMBOLO (`type == :all`), mas o controller manda STRING
  #    ('all' / 'read'). Mesmo com a aridade certa, nenhum ramo casaria e nada seria apagado.
  def perform(user_id, account_id, type: :all)
    user = User.find_by(id: user_id)
    account = Account.find_by(id: account_id)
    return if user.blank? || account.blank?

    notifications = user.notifications.where(account_id: account.id)

    ActiveRecord::Base.transaction do
      case type.to_sym
      when :all then notifications.destroy_all
      when :read then notifications.where.not(read_at: nil).destroy_all
      end
    end
  end
end
