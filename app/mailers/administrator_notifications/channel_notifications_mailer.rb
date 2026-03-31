class AdministratorNotifications::ChannelNotificationsMailer < AdministratorNotifications::BaseMailer
  def facebook_disconnect(inbox)
    subject = 'Your Facebook Page connection has expired'
    send_notification(subject, action_url: inbox_url(inbox))
  end

  def instagram_disconnect(inbox)
    subject = 'Your Instagram connection has expired'
    send_notification(subject, action_url: inbox_url(inbox))
  end

  def tiktok_disconnect(inbox)
    subject = 'Your TikTok connection has expired'
    send_notification(subject, action_url: inbox_url(inbox))
  end

  def whatsapp_disconnect(inbox)
    subject = 'Your WhatsApp connection has expired'
    send_notification(subject, action_url: inbox_url(inbox))
  end

  def email_disconnect(inbox)
    subject = 'Your email inbox has been disconnected. Please update SMTP/IMAP credentials'
    send_notification(subject, action_url: inbox_url(inbox))
  end
end
