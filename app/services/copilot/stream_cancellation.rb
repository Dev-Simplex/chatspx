# Sinal explicito de "pare esta geracao", compartilhado entre processos.
#
# Por que existe: fechar a conexao TAMBEM cancela, mas a deteccao depende do
# buffer de socket encher — medido contra a OpenAI real, o servidor seguiu
# gerando ~4s depois de o agente sair, porque tokens sao pequenos e demoram a
# encher o buffer. Isso e dinheiro do cliente queimado. Com o botao "parar"
# batendo em DELETE .../stream, a proxima checagem (no maximo 200ms depois)
# derruba a geracao.
#
# A flag mora no Redis porque quem gera e quem cancela podem estar em processos
# Puma diferentes.
class Copilot::StreamCancellation
  KEY_FORMAT = 'COPILOT_STREAM_CANCEL::%<thread_id>d'.freeze
  TTL_SECONDS = 120
  # Uma consulta ao Redis por token seria uma ida a rede por palavra digitada.
  CHECK_INTERVAL_SECONDS = 0.2

  def initialize(copilot_thread_id)
    @key = format(KEY_FORMAT, thread_id: copilot_thread_id.to_i)
    @checked_at = nil
    @requested = false
  end

  def request!
    Redis::Alfred.set(@key, Time.now.to_f.to_s, ex: TTL_SECONDS)
    true
  end

  def clear!
    Redis::Alfred.delete(@key)
    @requested = false
    @checked_at = nil
    true
  end

  def requested?
    return @requested if @requested
    return @requested if @checked_at && (monotonic_time - @checked_at) < CHECK_INTERVAL_SECONDS

    @checked_at = monotonic_time
    @requested = Redis::Alfred.exists?(@key)
  end

  private

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
