# frozen_string_literal: true

# Cache curto do status das sessoes da WAHA.
#
# Motivacao (GlitchTip issue 27 — 2.812 Net::ReadTimeout em 20 dias): bater num
# endpoint de sessao que NAO esta WORKING nao devolve erro rapido. Medido nesta
# VM: `GET /api/simplexteste/lids/{lid}` levou 10,22s para dizer 422, enquanto o
# `Waha::ApiService` corta em 8s (DEFAULT_TIMEOUT). O 422 tratavel nunca chega —
# vira Net::ReadTimeout -> ConnectionError -> ruido eterno.
#
# Por que cache e nao uma consulta por LID: `GET /api/sessions` responde em ~0,1s
# e ja traz TODAS as sessoes. Consultar por LID trocaria um problema por outro
# (uma chamada extra por item). Com TTL de 60s, uma execucao do sweep — que
# enfileira N jobs — paga UMA chamada, e uma sessao que volta a WORKING e
# reconhecida em no maximo um minuto (nao atrasa recuperacao legitima).
#
# Fail-open por desenho: quando nao da para saber o status (WAHA fora, Redis
# fora, resposta inesperada), `usable?` devolve true e o chamador segue com o
# comportamento antigo. O objetivo e cortar a chamada *sabidamente* inutil, nunca
# bloquear resolucao por falta de informacao.
class Waha::SessionStatusCache
  KEY = 'waha:sessions:working'
  # Marca "nao consegui perguntar". Sem ela, com a WAHA fora, cada job repetiria a
  # consulta — trocariamos um timeout por LID por outro. 15s: curto o bastante para
  # nao atrasar a volta da WAHA, longo o bastante para cobrir uma rajada de jobs.
  UNKNOWN_KEY = 'waha:sessions:unknown'
  TTL = 60
  UNKNOWN_TTL = 15
  WORKING = 'WORKING'

  class << self
    # Array com os nomes das sessoes WORKING, ou nil quando o status e desconhecido.
    def working_sessions
      cached = read_cache
      return cached unless cached.nil?
      return nil if unknown_recently?

      fetch_and_cache
    end

    # true  -> sessao esta WORKING (ou status desconhecido: fail-open)
    # false -> sessao existe na WAHA mas nao esta WORKING, ou nome em branco
    def usable?(session_name)
      return false if session_name.blank?

      sessions = working_sessions
      return true if sessions.nil?

      sessions.include?(session_name.to_s)
    end

    # Invalida o cache (usado em spec e quando se quer forcar releitura).
    def reset!
      Redis::Alfred.delete(KEY)
      Redis::Alfred.delete(UNKNOWN_KEY)
      true
    rescue StandardError => e
      log_failure('reset!', e)
      false
    end

    private

    def unknown_recently?
      Redis::Alfred.get(UNKNOWN_KEY).present?
    rescue StandardError
      false
    end

    def read_cache
      raw = Redis::Alfred.get(KEY)
      return nil if raw.nil?

      parsed = JSON.parse(raw)
      parsed.is_a?(Array) ? parsed : nil
    rescue StandardError => e
      log_failure('read', e)
      nil
    end

    def fetch_and_cache
      names = Array(Waha::ApiService.new.list_sessions).filter_map do |session|
        session['name'] if session.is_a?(Hash) && session['status'].to_s.upcase == WORKING
      end
      write_cache(names)
      names
    rescue StandardError => e
      # Inclui Waha::ApiService::Error e qualquer falha de rede: status desconhecido,
      # e quem chama nao pode ser bloqueado por isso.
      log_failure('list_sessions', e)
      mark_unknown
      nil
    end

    def mark_unknown
      Redis::Alfred.set(UNKNOWN_KEY, '1', ex: UNKNOWN_TTL)
    rescue StandardError
      false
    end

    def write_cache(names)
      Redis::Alfred.set(KEY, names.to_json, ex: TTL)
    rescue StandardError => e
      log_failure('write', e)
      false
    end

    def log_failure(operation, error)
      Rails.logger.warn("[WahaSessionStatusCache] #{operation} falhou: #{error.class} #{error.message}")
    end
  end
end
