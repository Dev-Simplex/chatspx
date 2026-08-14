# frozen_string_literal: true

# Cache Redis do mapa LID -> telefone da WAHA.
#
# Motivacao: num grupo movimentado, resolver o telefone do participante batendo
# `GET /api/{session}/lids/{lid}` a cada mensagem derruba a ingestao (o
# `Waha::ApiService` tem timeout de 8s e nao ha circuit breaker por LID). Uma
# leitura de Redis custa microssegundos e o mapa muda pouco.
#
# CONTRATO COMPARTILHADO — a chave e consumida por mais de um caminho:
#   chave  : "waha:lid_pn:{session}:{lid}"  (lid SO DIGITOS, sem "@lid")
#   valor  : telefone E.164 sem "+" (ex.: "5566999991234")
#            string VAZIA = "sabidamente nao resolvivel agora" (cache negativo,
#            TTL curto, evita martelar a WAHA por um LID que ela nao conhece)
#
# `write_many` existe para o caminho de sync de grupos popular o mapa em lote a
# partir do payload de `/groups`, sem um round-trip por participante.
#
# Redis fora do ar NAO pode derrubar a ingestao: toda operacao aqui degrada para
# nil/false com log, nunca levanta.
class Whatsapp::LidPhoneCache
  KEY_PREFIX = 'waha:lid_pn'
  RESOLVED_TTL = 7.days
  UNRESOLVED_TTL = 10.minutes
  UNRESOLVED = ''

  # Memoria de falha por LID (GlitchTip issue 27). O cache negativo acima tem TTL
  # de 10 min — certo para a ingestao de mensagem, inutil contra um job de cadencia
  # HORARIA: expira sempre entre duas execucoes do cron e nao freia nada. Aqui o
  # freio e um backoff que cresce com o numero de ciclos falhos, guardado em duas
  # chaves Redis (nada de tabela nova):
  #   waha:lid_pn:fail:{sessao}:{lid}     -> contador de ciclos falhos
  #   waha:lid_pn:cooldown:{sessao}:{lid} -> marca viva enquanto vale o backoff
  # O primeiro fracasso ja pula um ciclo inteiro do sweep (1h) e o teto e 7 dias,
  # que e o dead-letter de fato: um LID que a WAHA nunca vai conhecer para de ser
  # martelado, mas volta a ser tentado sozinho — nao precisa de intervencao.
  FAILURE_KEY_PREFIX = "#{KEY_PREFIX}:fail".freeze
  COOLDOWN_KEY_PREFIX = "#{KEY_PREFIX}:cooldown".freeze
  FAILURE_TTL = 30.days
  RETRY_BACKOFF = [1.hour, 2.hours, 6.hours, 12.hours, 1.day, 3.days, 7.days].freeze

  class << self
    def key(session_name, lid)
      "#{KEY_PREFIX}:#{session_name}:#{normalize_lid(lid)}"
    end

    def failure_key(session_name, lid)
      "#{FAILURE_KEY_PREFIX}:#{session_name}:#{normalize_lid(lid)}"
    end

    def cooldown_key(session_name, lid)
      "#{COOLDOWN_KEY_PREFIX}:#{session_name}:#{normalize_lid(lid)}"
    end

    # Valor cru do cache: telefone, string vazia (negativo) ou nil (miss).
    def read(session_name, lid)
      return nil if blank_key?(session_name, lid)

      value = Redis::Alfred.get(key(session_name, lid))
      return nil if value.nil?

      normalize_phone(value)
    rescue StandardError => e
      log_failure('read', e)
      nil
    end

    # Telefone em digitos ou nil — nao distingue miss de negativo.
    def phone(session_name, lid)
      read(session_name, lid).presence
    end

    # true quando o LID ja foi consultado e a WAHA nao soube responder.
    def unresolved?(session_name, lid)
      read(session_name, lid) == UNRESOLVED
    end

    def write(session_name, lid, phone)
      digits = normalize_phone(phone)
      return write_unresolved(session_name, lid) if digits.blank?
      return false if blank_key?(session_name, lid)

      Redis::Alfred.set(key(session_name, lid), digits, ex: RESOLVED_TTL.to_i)
      true
    rescue StandardError => e
      log_failure('write', e)
      false
    end

    def write_unresolved(session_name, lid)
      return false if blank_key?(session_name, lid)

      Redis::Alfred.set(key(session_name, lid), UNRESOLVED, ex: UNRESOLVED_TTL.to_i)
      true
    rescue StandardError => e
      log_failure('write_unresolved', e)
      false
    end

    # true enquanto vale o backoff deste LID — quem le deve PULAR a chamada a WAHA.
    # Fail-open: Redis fora devolve false (tenta), nunca trava a resolucao.
    def cooling_down?(session_name, lid)
      return false if blank_key?(session_name, lid)

      Redis::Alfred.get(cooldown_key(session_name, lid)).present?
    rescue StandardError => e
      log_failure('cooling_down?', e)
      false
    end

    # Registra UM ciclo falho e reabre o backoff; devolve o numero de ciclos.
    # Deve ser chamado uma vez por ciclo (nao por retry interno do job), senao as
    # 7 tentativas do `retry_on` levam o LID direto ao teto no primeiro ciclo.
    def record_failure(session_name, lid)
      return 0 if blank_key?(session_name, lid)

      count = Redis::Alfred.incr(failure_key(session_name, lid)).to_i
      Redis::Alfred.expire(failure_key(session_name, lid), FAILURE_TTL.to_i)
      Redis::Alfred.set(cooldown_key(session_name, lid), count.to_s, ex: backoff_for(count))
      count
    rescue StandardError => e
      log_failure('record_failure', e)
      0
    end

    def failure_count(session_name, lid)
      return 0 if blank_key?(session_name, lid)

      Redis::Alfred.get(failure_key(session_name, lid)).to_i
    rescue StandardError => e
      log_failure('failure_count', e)
      0
    end

    # Chamado no sucesso: o LID resolveu, a memoria de falha nao vale mais.
    def clear_failures(session_name, lid)
      return false if blank_key?(session_name, lid)

      Redis::Alfred.delete(failure_key(session_name, lid))
      Redis::Alfred.delete(cooldown_key(session_name, lid))
      true
    rescue StandardError => e
      log_failure('clear_failures', e)
      false
    end

    # Segundos de espera para o N-esimo ciclo falho (satura no ultimo degrau).
    def backoff_for(count)
      index = [count.to_i, 1].max - 1
      (RETRY_BACKOFF[index] || RETRY_BACKOFF.last).to_i
    end

    # Popula o mapa em lote a partir do payload de `/groups`; devolve quantas
    # entradas foram gravadas. Aceita Hash ({lid => phone}) OU Array de pares
    # ([[lid, phone], ...]) — o parser de participantes da WAHA devolve array, e
    # exigir Hash aqui fazia o lote inteiro virar no-op silencioso. Os dois lados
    # aceitam o JID cru ("229480102662169@lid" => "5566999991234@c.us").
    # Usa pipeline porque o payload de /groups traz ~900 pares de uma vez.
    #
    # ⚠️ INVARIANTE FRAGIL — LEIA ANTES DE MEXER OU DE ATUALIZAR A GEM.
    # Este e o UNICO ponto do cache que fala com o pool cru (`$alfred`) em vez de
    # `Redis::Alfred`. `$alfred` guarda um `Redis::Namespace.new('alfred', ...)`
    # (config/initializers/01_redis.rb:10), e isto so grava na mesma chave fisica
    # que o `read` procura porque `redis-namespace` tambem namespaceia o bloco
    # `pipelined` (1.10.0, lib/redis/namespace.rb:311). Se um upgrade major parar
    # de fazer isso, o lote vai para `waha:lid_pn:*` enquanto a leitura procura em
    # `alfred:waha:lid_pn:*`: cache 100% miss, sem erro, sem sintoma — so lentidao.
    # O spec "chave fisica" (spec/services/whatsapp/lid_phone_cache_spec.rb) compara
    # o prefixo real gravado por `write_many` com o de `write` e quebra se divergirem.
    def write_many(session_name, mapping)
      pairs = normalize_pairs(session_name, mapping)
      return 0 if pairs.empty?

      $alfred.with do |conn| # rubocop:disable Style/GlobalVars
        conn.pipelined do |pipeline|
          pairs.each { |cache_key, digits| pipeline.setex(cache_key, RESOLVED_TTL.to_i, digits) }
        end
      end
      pairs.size
    rescue StandardError => e
      log_failure('write_many', e)
      0
    end

    # Digitos do LID: aceita "229480102662169" e "229480102662169@lid".
    def normalize_lid(lid)
      lid.to_s.split('@').first.to_s.gsub(/\D/, '')
    end

    # Digitos do telefone: aceita "5566999991234", "+5566999991234" e
    # "5566999991234@c.us". String vazia continua vazia (cache negativo).
    def normalize_phone(phone)
      phone.to_s.split('@').first.to_s.gsub(/\D/, '')
    end

    private

    def normalize_pairs(session_name, mapping)
      return [] if session_name.blank? || mapping.blank?

      Array(mapping).filter_map do |lid, phone|
        digits = normalize_phone(phone)
        next if digits.blank? || normalize_lid(lid).blank?

        [key(session_name, lid), digits]
      end.uniq(&:first)
    end

    def blank_key?(session_name, lid)
      session_name.blank? || normalize_lid(lid).blank?
    end

    def log_failure(operation, error)
      Rails.logger.warn("[LidPhoneCache] #{operation} falhou: #{error.class} #{error.message}")
    end
  end
end
