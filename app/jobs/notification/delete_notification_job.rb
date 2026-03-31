class Notification::DeleteNotificationJob < ApplicationJob
  queue_as :low

  def perform(user_id, type: 'all')
    user = User.find_by(id: user_id)
    return unless user

    ActiveRecord::Base.transaction do
      if type == 'all'
        # Delete all notifications
        user.notifications.destroy_all
      elsif type == 'read'
        # Delete only read notifications
        user.notifications.where.not(read_at: nil).destroy_all
      end
    end
  end
end
