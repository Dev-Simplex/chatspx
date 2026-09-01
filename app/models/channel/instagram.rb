# == Schema Information
#
# Table name: channel_instagram
#
#  id           :bigint           not null, primary key
#  access_token :string           not null
#  expires_at   :datetime         not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :integer          not null
#  instagram_id :string           not null
#
# Indexes
#
#  index_channel_instagram_on_instagram_id  (instagram_id) UNIQUE
#
class Channel::Instagram < ApplicationRecord
  include Channelable
  include Reauthorizable
  self.table_name = 'channel_instagram'

  # TODO: Remove guard once encryption keys become mandatory (target 3-4 releases out).
  encrypts :access_token if Chatwoot.encryption_configured?

  AUTHORIZATION_ERROR_THRESHOLD = 1

  validates :access_token, presence: true
  validates :instagram_id, uniqueness: true, presence: true

  after_create_commit :subscribe
  before_destroy :unsubscribe

  def name
    'Instagram'
  end

  # `message.attachments[]` aceita até 30 imagens numa requisição só (medido ao vivo em
  # 18/08: HTTP 200 com message_id, renderiza em todo lugar e volta como eco).
  def supports_multi_image_message?
    true
  end

  # Generic template, até 10 cards (medido ao vivo em 18/08). Duas limitações conhecidas e
  # aceitas: renderiza no app do celular, mas o Instagram Web mostra "Mensagem não aceita —
  # use o app do Instagram para celular"; e a Meta NÃO devolve eco dele — o painel só não
  # fica cego porque o SPX cria a Message local antes de entregar.
  def supports_card_carousel?
    true
  end

  def create_contact_inbox(instagram_id, name)
    @contact_inbox = ::ContactInboxWithContactBuilder.new({
                                                            source_id: instagram_id,
                                                            inbox: inbox,
                                                            contact_attributes: { name: name }
                                                          }).perform
  end

  # O mínimo que faz a DM existir. Nunca sai da assinatura.
  CORE_SUBSCRIBED_FIELDS = %w[messages message_reactions messaging_seen].freeze

  # Campos de webhook assinados NA CONTA de Instagram. Quais são assináveis depende das
  # permissões do app da box — daí ser configuração de instalação, irmã de `INSTAGRAM_SCOPES`.
  #
  # Foi por não existir esta chave que ligar `comments` para a BigStore em 18/08 teve de ser
  # feito por chamada de API à mão, fora do produto.
  def subscribed_fields
    extras = GlobalConfigService.load('INSTAGRAM_SUBSCRIBED_FIELDS', '').to_s.split(',').map(&:strip).compact_blank

    (CORE_SUBSCRIBED_FIELDS + extras).uniq
  end

  # ref https://developers.facebook.com/docs/instagram-platform/webhooks#enable-subscriptions
  #
  # DOIS DEFEITOS CONSERTADOS AQUI:
  #
  # 1. O retorno era ignorado. `HTTParty.post` NÃO levanta exceção em HTTP 400 — então o
  #    `rescue StandardError` só pegava falha de rede, e uma recusa da Meta passava por sucesso.
  #    O canal ficava sem assinatura e nada em lugar nenhum dizia isso.
  # 2. A lista vai inteira numa chamada só. Um campo que o app da box não tem derruba o LOTE, e
  #    o canal ficaria sem assinatura NENHUMA — DM morta em silêncio. Agora, se o lote completo
  #    for recusado, recua-se para o mínimo que mantém a DM viva, dizendo o que se perdeu.
  def subscribe
    campos = subscribed_fields
    return true if subscribe_fields(campos)
    return false if campos == CORE_SUBSCRIBED_FIELDS

    Rails.logger.error(
      "[instagram] assinatura completa recusada para #{instagram_id}; " \
      "recuando para #{CORE_SUBSCRIBED_FIELDS.join(',')} — os campos extras NÃO estão assinados"
    )
    subscribe_fields(CORE_SUBSCRIBED_FIELDS)
  end

  def unsubscribe
    HTTParty.delete(
      "https://graph.instagram.com/v22.0/#{instagram_id}/subscribed_apps",
      query: {
        access_token: access_token
      }
    )
    true
  rescue StandardError => e
    Rails.logger.debug { "Rescued: #{e.inspect}" }
    true
  end

  def access_token
    Instagram::RefreshOauthTokenService.new(channel: self).access_token
  end

  private

  def subscribe_fields(campos)
    response = HTTParty.post(
      "https://graph.instagram.com/#{api_version}/#{instagram_id}/subscribed_apps",
      query: {
        subscribed_fields: campos,
        access_token: access_token
      }
    )
    return true if response.success? && error_de(response).blank?

    Rails.logger.error(
      "[instagram] falha ao assinar #{campos.join(',')} em #{instagram_id}: " \
      "HTTP #{response.code} #{response.body}"
    )
    false
  rescue StandardError => e
    Rails.logger.error("[instagram] erro ao assinar #{campos.join(',')} em #{instagram_id}: #{e.message}")
    false
  end

  def error_de(response)
    corpo = response.parsed_response
    corpo.is_a?(Hash) ? corpo['error'] : nil
  end

  def api_version
    GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0')
  end
end
