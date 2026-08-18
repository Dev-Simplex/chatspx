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

  # Campos de webhook que TODA box assina. É lista global: mexer aqui muda toda conta em
  # toda VM, e o app da Meta é um por VM — cada um com o seu conjunto de permissões.
  BASE_WEBHOOK_FIELDS = %w[messages message_reactions messaging_seen].freeze

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

  def create_contact_inbox(instagram_id, name)
    @contact_inbox = ::ContactInboxWithContactBuilder.new({
                                                            source_id: instagram_id,
                                                            inbox: inbox,
                                                            contact_attributes: { name: name }
                                                          }).perform
  end

  # ref https://developers.facebook.com/docs/instagram-platform/webhooks#enable-subscriptions
  #
  # A Meta assina a lista INTEIRA numa chamada só: um campo que o app daquela box não tem
  # direito de receber derruba a chamada toda, e antes o erro morria num `rescue` de debug —
  # o canal ficava sem assinatura nenhuma e o DM morria em silêncio. Por isso o campo extra é
  # opcional de verdade: se a assinatura com ele falhar, reassina os obrigatórios antes de
  # desistir, e as duas falhas ficam no log em nível de erro.
  def subscribe
    fields = webhook_fields
    return true if subscribe_to(fields)
    return true if fields != BASE_WEBHOOK_FIELDS && subscribe_to(BASE_WEBHOOK_FIELDS)

    false
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

  # Campos além dos obrigatórios, POR INSTALAÇÃO. Vazio por padrão: enquanto ninguém ligar,
  # toda box assina exatamente o que assinava antes. `messaging_postbacks` é o que devolve o
  # clique nos botões dos cards, e só deve entrar em box cujo app da Meta tenha esse campo.
  def webhook_fields
    extra = GlobalConfigService.load('INSTAGRAM_WEBHOOK_EXTRA_FIELDS', '').to_s.split(',').map(&:strip).reject(&:blank?)
    (BASE_WEBHOOK_FIELDS + extra).uniq
  end

  def subscribe_to(fields)
    response = HTTParty.post(
      "https://graph.instagram.com/v22.0/#{instagram_id}/subscribed_apps",
      query: {
        subscribed_fields: fields,
        access_token: access_token
      }
    )
    return true if subscription_ok?(response)

    Rails.logger.error("[Instagram] assinatura recusada (channel #{id}, campos #{fields.join(',')}): #{response.body}")
    false
  rescue StandardError => e
    Rails.logger.error("[Instagram] assinatura falhou (channel #{id}, campos #{fields.join(',')}): #{e.inspect}")
    false
  end

  # A Meta responde 200 com `error` no corpo em parte dos casos — status HTTP sozinho não
  # diz se a assinatura pegou.
  def subscription_ok?(response)
    return false unless response.success?

    parsed = response.parsed_response
    !(parsed.is_a?(Hash) && parsed['error'].present?)
  end
end
