class Notification::DeleteNotificationJob < ApplicationJob
  queue_as :low

  def perform(user, account, type: :all)
    # ChatSPX (C-21): o escopo por conta do upstream é correto e fica. O que se recupera aqui é a
    # defensividade que a nossa versão tinha (ela recebia ids e fazia `return unless user`):
    # passando objetos AR, o job serializa por GlobalID e estoura ActiveJob::DeserializationError
    # se o usuário ou a conta forem apagados antes de o job rodar.
    return if user.blank? || account.blank?

    notifications = user.notifications.where(account_id: account.id)

    ActiveRecord::Base.transaction do
      if type == :all
        notifications.destroy_all
      elsif type == :read
        notifications.where.not(read_at: nil).destroy_all
      end
    end
  end
end
