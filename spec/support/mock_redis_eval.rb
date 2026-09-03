# frozen_string_literal: true

# MockRedis (usado no lugar do Redis em `config/initializers/01_redis.rb` quando
# `Rails.env.test?`) NAO implementa `eval` — nao ha interpretador Lua nele.
#
# Pior que a ausencia e o sintoma: `redis-namespace` despacha os comandos por
# `send(:eval, ...)`, e `send` FURA o `private`. Como todo objeto Ruby herda o
# `Kernel#eval` privado, a chamada caia nele e o erro que aparecia era
# `TypeError: wrong argument type Hash (expected binding)` — que nao menciona Redis, Lua nem
# MockRedis, e manda o leitor investigar o lugar errado.
#
# Em PRODUCAO nada disso acontece: o cliente interno e um Redis de verdade e o script roda no
# servidor. Isto aqui e exclusivamente um dublê de teste.
#
# Regra deliberada: executa SO os scripts que conhecemos, comparando o texto. Script
# desconhecido LEVANTA. Um `eval` generico que devolvesse `nil` faria specs passarem sem que
# a logica atomica tivesse rodado — verde por ausencia de sujeito, exatamente o que nao
# queremos aqui.
if defined?(MockRedis)
  class MockRedis
    # `redis-namespace` normaliza os argumentos antes de despachar, entao `keys`/`argv` podem
    # chegar como kwargs OU como dois arrays posicionais OU como um unico Hash posicional.
    # Aceitamos as tres formas: fixar uma so quebra conforme a versao do gem.
    def eval(script, *args, **kwargs)
      keys, argv = normaliza_argumentos(args, kwargs)
      texto = script.to_s.strip
      return inflight_acquire_simulado(keys, argv) if texto == Waha::MessageStatusSyncService::INFLIGHT_ACQUIRE.strip

      raise NotImplementedError,
            'MockRedis#eval: script Lua desconhecido. Implemente a simulacao em ' \
            "spec/support/mock_redis_eval.rb antes de usa-lo em teste.\n#{texto}"
    end

    private

    def normaliza_argumentos(args, kwargs)
      opcoes = kwargs.empty? && args.first.is_a?(Hash) ? args.first : kwargs
      keys = opcoes[:keys] || opcoes['keys'] || posicional_array(args, 0)
      argv = opcoes[:argv] || opcoes['argv'] || posicional_array(args, 1)
      [keys, argv]
    end

    def posicional_array(args, indice)
      args[indice].is_a?(Array) ? args[indice] : []
    end

    # Equivalente Ruby do INFLIGHT_ACQUIRE: poda os membros vencidos por score, recusa se
    # o conjunto ja esta no teto, senao reserva a vaga e renova o TTL.
    def inflight_acquire_simulado(keys, argv)
      chave = keys.first
      agora = argv[0].to_f
      ttl = argv[1].to_f
      maximo = argv[2].to_i
      membro = argv[3].to_s

      zremrangebyscore(chave, 0, agora - ttl)
      return 0 if zcard(chave) >= maximo

      zadd(chave, agora, membro)
      expire(chave, (ttl + 5).to_i)
      1
    end
  end
end
