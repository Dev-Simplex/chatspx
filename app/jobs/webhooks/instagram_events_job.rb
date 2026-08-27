class Webhooks::InstagramEventsJob < MutexApplicationJob
  queue_as :default
  retry_on LockAcquisitionError, wait: 1.second, attempts: 8

  # @return [Array] We will support further events like reaction or seen in future
  SUPPORTED_EVENTS = [:message, :postback, :read].freeze

  # Campos que chegam em `changes` (e não em `messaging`) e que sabemos tratar. Campo fora desta
  # lista é registrado e ignorado — nunca silenciosamente descartado, que era o defeito antigo.
  SUPPORTED_CHANGE_FIELDS = %w[comments].freeze

  def perform(entries)
    @entries = entries

    key = format(::Redis::Alfred::IG_MESSAGE_MUTEX, sender_id: lock_subject, ig_account_id: ig_account_id)
    with_lock(key) do
      process_entries(entries)
    end
  end

  # https://developers.facebook.com/docs/messenger-platform/instagram/features/webhook
  def process_entries(entries)
    entries.each do |entry|
      process_single_entry(entry.with_indifferent_access)
    end
  end

  private

  def process_single_entry(entry)
    if test_event?(entry)
      process_test_event(entry)
    elsif entry[:changes].present?
      process_changes(entry)
    else
      process_messages(entry)
    end
  end

  # Eventos que a Meta entrega em `changes` — hoje, comentário público.
  #
  # O canal se acha por `entry[:id]` (o id da conta de Instagram), e NÃO por
  # `messaging.recipient.id` como nas DMs: comentário não tem destinatário.
  def process_changes(entry)
    channel = find_channel(entry[:id])
    return if channel.blank?

    entry[:changes].each do |change|
      field = change[:field].to_s

      unless SUPPORTED_CHANGE_FIELDS.include?(field)
        Rails.logger.info("Instagram Events Job: campo `#{field}` ainda sem tratamento, ignorado")
        next
      end

      comment(change[:value], channel, entry[:time])
    end
  end

  def comment(value, channel, time)
    return if value.blank?

    ::Spx::Social::InstagramComentarioService.new(
      value: value,
      channel: channel,
      ocorrido_em: event_time(time)
    ).perform
  end

  def event_time(time)
    return if time.blank?

    Time.zone.at(time.to_i)
  end

  def process_messages(entry)
    messages(entry).each do |messaging|
      Rails.logger.info("Instagram Events Job Messaging: #{messaging}")

      instagram_id = instagram_id(messaging)
      channel = find_channel(instagram_id)

      next if channel.blank?

      if (event_name = event_name(messaging))
        send(event_name, messaging, channel)
      end
    end
  end

  def agent_message_via_echo?(messaging)
    messaging[:message].present? && messaging[:message][:is_echo].present?
  end

  # O payload de teste do painel da Meta chega com `entry.id == "0"` — está descrito no comentário
  # no fim deste arquivo desde que ele existe, e o `TestEventService` ainda confere o sender
  # `12334` por cima disso.
  #
  # O discriminador anterior era `entry[:changes].present?`, e essa é a razão de TODO comentário
  # público ser descartado em silêncio: comentário real também chega em `changes`, então passava
  # por evento de teste, não casava com o sender de teste e morria sem rastro nenhum.
  def test_event?(entry)
    entry[:id].to_s == '0'
  end

  def process_test_event(entry)
    messaging = extract_messaging_from_test_event(entry)

    Instagram::TestEventService.new(messaging).perform if messaging.present?
  end

  def extract_messaging_from_test_event(entry)
    entry[:changes].first&.dig(:value) if entry[:changes].present?
  end

  def instagram_id(messaging)
    if agent_message_via_echo?(messaging)
      messaging[:sender][:id]
    else
      messaging[:recipient][:id]
    end
  end

  def ig_account_id
    @entries&.first&.dig(:id)
  end

  # Numa DM o lock serializa por CONTATO; num comentário, pelo próprio comentário.
  #
  # Sem essa distinção `contact_instagram_id` seria nil e todo comentário da conta disputaria a
  # mesma chave: uma publicação com muitos comentários ao mesmo tempo perderia comentário por
  # falha de lock — exatamente o que este job deixou de fazer.
  def lock_subject
    contact_instagram_id || first_change_id
  end

  def first_change_id
    @entries&.first&.dig(:changes, 0, :value, :id)
  end

  def contact_instagram_id
    entry = @entries&.first
    return nil unless entry

    # Handle both messaging and standby arrays
    messaging = (entry[:messaging].presence || entry[:standby] || []).first
    return nil unless messaging

    # For echo messages (outgoing from our account), use recipient's ID (the contact)
    # For incoming messages (from contact), use sender's ID (the contact)
    if messaging.dig(:message, :is_echo)
      messaging.dig(:recipient, :id)
    else
      messaging.dig(:sender, :id)
    end
  end

  def sender_id
    @entries&.dig(0, :messaging, 0, :sender, :id)
  end

  def find_channel(instagram_id)
    # There will be chances for the instagram account to be connected to a facebook page,
    # so we need to check for both instagram and facebook page channels
    # priority is for instagram channel which created via instagram login
    channel = Channel::Instagram.find_by(instagram_id: instagram_id)
    # If not found, fallback to the facebook page channel
    channel ||= Channel::FacebookPage.find_by(instagram_id: instagram_id)

    channel
  end

  # Sem memoização: um entry pode trazer mais de um messaging, e com três tipos de evento o
  # primeiro passaria a decidir o handler de todos — um clique de botão seria despachado
  # como `message` (ou vice-versa) só por ter vindo no mesmo lote.
  def event_name(messaging)
    SUPPORTED_EVENTS.find { |key| messaging.key?(key) }
  end

  def message(messaging, channel)
    if channel.is_a?(Channel::Instagram)
      ::Instagram::MessageText.new(messaging, channel).perform
    else
      ::Instagram::Messenger::MessageText.new(messaging, channel).perform
    end
  end

  # Clique no botão de um card. Só processa em canal que DESENHA card: onde a vitrine não
  # existe, um postback vem de outra coisa (menu fixo, ice breaker) e virar mensagem mudaria
  # o comportamento de quem nunca pediu isso.
  def postback(messaging, channel)
    return unless channel.supports_card_carousel?

    message(normalize_postback(messaging), channel)
  end

  # O postback não traz `message`, mas traz mid, título e payload. Normalizado pro formato de
  # mensagem, reusa o caminho inteiro (contato, conversa, dedupe por mid): o título vira o
  # conteúdo e o payload fica em content_attributes, como o botão do WhatsApp já faz.
  def normalize_postback(messaging)
    data = messaging[:postback]
    messaging.merge(message: { mid: data[:mid], text: data[:title] })
  end

  def read(messaging, channel)
    # Use a single service to handle read status for both channel types since the params are same
    ::Instagram::ReadStatusService.new(params: messaging, channel: channel).perform
  end

  def messages(entry)
    (entry[:messaging].presence || entry[:standby] || [])
  end
end

# Actual response from Instagram webhook (both via Facebook page and Instagram direct)
# [
#   {
#     "time": <timestamp>,
#     "id": <INSTAGRAM_USER_ID>,
#     "messaging": [
#       {
#         "sender": {
#           "id": <INSTAGRAM_USER_ID>
#         },
#         "recipient": {
#           "id": <INSTAGRAM_USER_ID>
#         },
#         "timestamp": <timestamp>,
#         "message": {
#           "mid": <MESSAGE_ID>,
#           "text": <MESSAGE_TEXT>
#         }
#       }
#     ]
#   }
# ]

# Instagram's webhook via Instagram direct testing quirk: Test payloads vs Actual payloads
# When testing in Facebook's developer dashboard, you'll get a Page-style
# payload with a "changes" object. But don't be fooled! Real Instagram DMs
# arrive in the familiar Messenger format with a "messaging" array.
# This apparent inconsistency is actually by design - Instagram's webhooks
# use different formats for testing vs production to maintain compatibility
# with both Instagram Direct and Facebook Page integrations.
# See: https://developers.facebook.com/docs/instagram-platform/webhooks#event-notifications

# Test response from via Instagram direct
# [
#   {
#     "id": "0",
#     "time": <timestamp>,
#     "changes": [
#       {
#         "field": "messages",
#         "value": {
#           "sender": {
#             "id": "12334"
#           },
#           "recipient": {
#             "id": "23245"
#           },
#           "timestamp": "1527459824",
#           "message": {
#             "mid": "random_mid",
#             "text": "random_text"
#           }
#         }
#       }
#     ]
#   }
# ]

# Test response via Facebook page
# [
#   {
#     "time": <timestamp>,,
#     "id": "0",
#     "messaging": [
#       {
#         "sender": {
#           "id": "12334"
#         },
#         "recipient": {
#           "id": "23245"
#         },
#         "timestamp": <timestamp>,
#         "message": {
#             "mid": "random_mid",
#             "text": "random_text"
#         }
#       }
#     ]
#   }
# ]
