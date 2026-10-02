# Conta os inbounds do WhatsApp descartados antes de virarem mensagem.
#
# O descarte acontece no Webhooks::WhatsappEventsJob e e SILENCIOSO por construcao: o controller ja
# respondeu 200 para a Meta, entao nao ha reentrega, e o unico sinal era uma linha de `warn` no log.
# Sem numero, o estado "esse numero nao recebe nada" fica indistinguivel de "ninguem escreveu hoje".
#
# TTL de 7 dias e de proposito: o contador responde "esta acontecendo AGORA?", nao "ja aconteceu
# alguma vez na vida". Cada descarte novo renova a janela.
class Whatsapp::DroppedInboundCounter
  TTL = 7.days.to_i

  REASONS = {
    channel_not_found: 'channel_not_found',
    reauthorization_required: 'reauthorization_required',
    account_inactive: 'account_inactive'
  }.freeze

  class << self
    def record(channel_key, reason)
      key = redis_key(channel_key, reason)
      ::Redis::Alfred.incr(key)
      ::Redis::Alfred.expire(key, TTL)
    end

    # { 'reauthorization_required' => 12 } — so os motivos que de fato aconteceram na janela.
    def counts(channel_key)
      ::Redis::Alfred.scan_each(match: redis_key(channel_key, '*')).each_with_object({}) do |key, contagem|
        contagem[key.split('::').last] = ::Redis::Alfred.get(key).to_i
      end
    end

    private

    def redis_key(channel_key, reason)
      format(::Redis::RedisKeys::WHATSAPP_DROPPED_INBOUND, channel_id: channel_key, reason: reason)
    end
  end
end
