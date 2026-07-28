# frozen_string_literal: true

# Descobre, a partir de uma conversa, (a) o JID do grupo de WhatsApp e (b) em qual
# sessao da WAHA esse grupo pode ser consultado.
#
# Por que (b) nao e trivial: `inbox.waha_session_name` so esta preenchido em parte
# das caixas. Nesta VM, por exemplo, as conversas de grupo vivem numa caixa cujo
# `waha_session_name` e nil, enquanto as duas caixas que declaram sessao apontam
# para sessoes que nao existem mais na WAHA. Por isso resolvemos em cascata e
# devolvemos CANDIDATAS em ordem de confianca, em vez de um palpite unico:
#
#   1. `inbox.waha_session_name`            — declaracao explicita do operador
#   2. indice Redis grupo -> sessao         — evidencia empirica: o RefreshGroupsJob
#                                             VIU este grupo naquela sessao
#   3. sessao embutida no webhook da WAHA   — .../webhooks/chatwoot/{session}/{app}
#   4. ENV['WAHA_DEFAULT_SESSION']          — desligado por padrao; so use quando a
#                                             VM tem uma WAHA dedicada
module Waha::GroupLocator
  GROUP_SESSION_KEY_PREFIX = 'waha:group_session'
  GROUP_SESSION_TTL = 7.days.to_i
  WEBHOOK_SESSION_PATTERN = %r{/webhooks/chatwoot/([^/]+)}

  module_function

  # JID do grupo (ex.: '556696571379-1634750731@g.us') ou nil se a conversa nao
  # for de grupo. Usa o mesmo dado que `Conversation#group?` (C1) ja olha.
  def group_id(conversation)
    return nil unless conversation&.group?

    contact = conversation.contact
    return nil if contact.blank?

    candidates = [contact.identifier, *(contact.custom_attributes || {}).values_at('waha_whatsapp_chat_id', 'waha_whatsapp_jid')]
    candidates.find { |jid| jid.to_s.end_with?(Conversation::WHATSAPP_GROUP_JID_SUFFIX) }
  end

  # Sessoes candidatas, em ordem de confianca, sem duplicatas.
  def session_candidates(conversation, group_id = nil)
    group_id ||= group_id(conversation)
    inbox = conversation&.inbox

    [
      inbox&.waha_session_name,
      indexed_session(group_id),
      session_from_webhook(inbox),
      ENV.fetch('WAHA_DEFAULT_SESSION', nil)
    ].filter_map { |name| name.to_s.presence }.uniq
  end

  # Registra "este grupo esta nesta sessao". Chamado pelo RefreshGroupsJob com os
  # JIDs que a propria WAHA devolveu — nao ha adivinhacao aqui.
  def index_sessions(session_name, group_ids)
    return 0 if session_name.blank?

    ids = Array(group_ids).filter_map { |jid| jid.to_s.presence }.uniq
    return 0 if ids.empty?

    $alfred.with do |redis| # rubocop:disable Style/GlobalVars
      redis.pipelined do |pipeline|
        ids.each { |jid| pipeline.setex(group_session_key(jid), GROUP_SESSION_TTL, session_name) }
      end
    end

    ids.size
  end

  def indexed_session(group_id)
    return nil if group_id.blank?

    Redis::Alfred.get(group_session_key(group_id)).presence
  end

  def group_session_key(group_id)
    "#{GROUP_SESSION_KEY_PREFIX}:#{group_id}"
  end

  # Caixas WAHA guardam o webhook no formato
  # https://<host-waha>/webhooks/chatwoot/{session}/{app}. So aceitamos quando o
  # host bate com o WAHA_API_URL configurado — webhook de outro provedor
  # (Evolution, por exemplo) nao diz nada sobre sessao da WAHA.
  def session_from_webhook(inbox)
    url = inbox&.channel.try(:webhook_url).to_s
    return nil if url.blank?
    return nil unless same_host_as_waha?(url)

    url[WEBHOOK_SESSION_PATTERN, 1]
  end

  def same_host_as_waha?(url)
    waha_host = URI.parse(ENV.fetch('WAHA_API_URL', '')).host
    return false if waha_host.blank?

    URI.parse(url).host == waha_host
  rescue URI::InvalidURIError
    false
  end
end
