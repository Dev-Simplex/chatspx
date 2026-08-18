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

  # O canal entrega VÁRIAS imagens numa única mensagem? Quem não entrega manda uma
  # requisição por anexo, como sempre — a pergunta só troca o empacotamento do envio,
  # não o que é enviado.
  def supports_multi_image_message?
    false
  end

  # O canal desenha a vitrine de cards que a mensagem carrega em content_attributes['cards']
  # (título, foto, subtítulo e um botão por card)? A lista é AGNÓSTICA de propósito: cada
  # canal a traduz pro formato dele. Quem não desenha NÃO falha — manda o `content` como
  # texto —, então, como no interactive_payload, a pergunta precisa ser feita por quem MONTA
  # a lista, antes de montá-la.
  def supports_card_carousel?
    false
  end
end

Channelable.prepend_mod_with('Channelable')
