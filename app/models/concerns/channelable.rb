module Channelable
  extend ActiveSupport::Concern
  included do
    validates :account_id, presence: true
    belongs_to :account
    has_one :inbox, as: :channel, dependent: :destroy_async, touch: true
    after_update :create_audit_log_entry
  end

  def create_audit_log_entry; end

  # O canal entrega o objeto `interactive` da Meta que a mensagem carrega em
  # content_attributes['interactive_payload'] (carrossel, cta_url, location_request, Flow)?
  # Só o WhatsApp Cloud lê essa chave — quem não lê NÃO falha: manda o `content` como texto
  # comum e a mensagem sai vazia de conteúdo real, sem erro em lugar nenhum. Por isso a
  # pergunta precisa ser feita por quem MONTA o payload, antes de montá-lo.
  def supports_interactive_payload?
    false
  end
end

Channelable.prepend_mod_with('Channelable')
