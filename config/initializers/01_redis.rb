# TODO: Phase out the custom ConnectionPool wrappers ($alfred / $velma),
# switch to plain Redis clients here and let Rails 7.1+ handle pooling
# via `pool:` in RedisCacheStore (see rack_attack initializer).

# ChatSPX: em teste, o bloco do ConnectionPool roda UMA VEZ POR CONEXAO -- e `MockRedis.new`
# dentro dele criava ate 15 armazenamentos INDEPENDENTES. Em producao as 15 conexoes falam com
# o MESMO servidor Redis, entao `SET NX` e uma trava de verdade; em teste, duas threads que
# pegassem conexoes diferentes nunca se enxergavam e o NX devolvia `true` para as duas.
#
# Medido nesta VM antes do conserto:
#   sequencial (mesma conexao reusada): 1 instancia
#   concorrente (5 threads):            5 instancias distintas
#   NX em duas conexoes:                primeira=true segunda=true   <- a trava nao travava
#
# O efeito nao era "um teste instavel": era toda invariante de exclusao mutua via Redis
# passando no VACUO -- o dublê nunca reproduzia a contencao que a trava existe para resolver.
# Nada muda para spec sequencial (o pool ja devolvia a mesma conexao, logo o mesmo
# armazenamento); o que muda e so o caso concorrente, que era justamente o quebrado.
MOCK_REDIS_COMPARTILHADO = MockRedis.new if Rails.env.test?

# Alfred
# Add here as you use it for more features
# Used for Round Robin, Conversation Emails & Online Presence
alfred_size = ENV.fetch('REDIS_ALFRED_SIZE', 15)
$alfred = ConnectionPool.new(size: alfred_size, timeout: 2) do
  redis = Rails.env.test? ? MOCK_REDIS_COMPARTILHADO : Redis.new(Redis::Config.app)
  Redis::Namespace.new('alfred', redis: redis, warning: true)
end

# Velma : Determined protector
# used in rack attack
velma_size = ENV.fetch('REDIS_VELMA_SIZE', 10)
$velma = ConnectionPool.new(size: velma_size, timeout: 2) do
  config = Rails.env.test? ? MOCK_REDIS_COMPARTILHADO : Redis.new(Redis::Config.app)
  Redis::Namespace.new('velma', redis: config, warning: true)
end
