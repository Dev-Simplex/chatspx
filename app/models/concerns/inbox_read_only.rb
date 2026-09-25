# CHAT-155: caixa somente leitura -- recebe, mas nada sai por ela. Opcionalmente aponta a caixa pela
# qual o atendente responde o cliente (redirect_reply).
module InboxReadOnly
  extend ActiveSupport::Concern

  included do
    belongs_to :read_only_redirect_inbox, class_name: 'Inbox', optional: true
    validate :ensure_valid_read_only_redirect_inbox, if: :read_only_redirect_inbox_id?
    before_save -> { self.read_only_redirect_inbox_id = nil }, unless: :read_only?
  end

  private

  # O destino tem de ser outra caixa da mesma conta que consiga enviar: WhatsApp (oficial ou WAHA) e
  # que nao seja ela mesma somente leitura.
  def ensure_valid_read_only_redirect_inbox
    target = read_only_redirect_inbox
    return if target && target.account_id == account_id && target.id != id && redirect_target_can_send?(target)

    errors.add(:read_only_redirect_inbox_id, I18n.t('errors.read_only_inbox.redirect_invalid'))
  end

  def redirect_target_can_send?(target)
    !target.read_only? && (target.whatsapp? || (target.api? && target.waha_session_name.present?))
  end
end
