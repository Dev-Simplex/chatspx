class AdministratorNotifications::AccountNotificationMailer < AdministratorNotifications::BaseMailer
  def account_deletion_user_initiated(account, reason)
    subject = 'Sua conta foi marcada para exclusão'
    action_url = settings_url('general')
    meta = {
      'account_name' => account.name,
      'deletion_date' => format_deletion_date(account.custom_attributes['marked_for_deletion_at']),
      'reason' => reason
    }

    send_notification(subject, action_url: action_url, meta: meta)
  end

  def account_deletion_for_inactivity(account, reason)
    subject = 'Sua conta Chatwoot está programada para exclusão devido à inatividade'
    action_url = settings_url('general')
    meta = {
      'account_name' => account.name,
      'deletion_date' => format_deletion_date(account.custom_attributes['marked_for_deletion_at']),
      'reason' => reason
    }

    send_notification(subject, action_url: action_url, meta: meta)
  end

  def contact_import_complete(resource)
    subject = 'Importação de Contatos Concluída'

    action_url = if resource.failed_records.attached?
                   Rails.application.routes.url_helpers.rails_blob_url(resource.failed_records)
                 else
                   "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{resource.account.id}/contacts"
                 end

    meta = {
      'failed_contacts' => resource.total_records - resource.processed_records,
      'imported_contacts' => resource.processed_records
    }

    send_notification(subject, action_url: action_url, meta: meta)
  end

  def contact_import_failed
    subject = 'Importação de Contatos Falhou'
    send_notification(subject)
  end

  def contact_export_complete(file_url, email_to)
    subject = "O arquivo de exportação dos seus contatos está disponível para download."
    send_notification(subject, to: email_to, action_url: file_url)
  end

  def automation_rule_disabled(rule)
    subject = 'Regra de automação desabilitada devido a erros de validação.'
    action_url = settings_url('automation/list')
    meta = { 'rule_name' => rule.name }

    send_notification(subject, action_url: action_url, meta: meta)
  end

  private

  def format_deletion_date(deletion_date_str)
    return 'Unknown' if deletion_date_str.blank?

    Time.zone.parse(deletion_date_str).strftime('%B %d, %Y')
  rescue StandardError
    'Unknown'
  end
end
