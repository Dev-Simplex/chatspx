# Escritor de Server-Sent Events do copiloto.
#
# Cuida de tres coisas que decidem a qualidade do streaming:
#
#   1. formato — um `id:` incremental por evento (abre caminho para retomada por
#      `Last-Event-ID` depois), `event:` nomeado e `data:` com JSON em uma linha;
#   2. keep-alive — comentario `: keep-alive` periodico numa thread propria. Sem
#      isso, proxy/loadbalancer derruba a conexao no silencio do TTFT;
#   3. deteccao de desconexao — o keep-alive tambem e sonda: se o agente fechou a
#      aba enquanto o LLM ainda estava calado, e o heartbeat que descobre e marca
#      `connected? == false`, permitindo abortar a geracao.
#
# Toda escrita passa por um mutex porque o heartbeat roda em outra thread.
class Copilot::SseStream
  # Cliente sumiu. Nao e erro de aplicacao: e o caminho normal de cancelamento.
  class Disconnected < StandardError; end

  DEFAULT_HEARTBEAT_SECONDS = 10

  def initialize(stream, heartbeat_interval: DEFAULT_HEARTBEAT_SECONDS)
    @stream = stream
    @heartbeat_interval = heartbeat_interval
    @mutex = Mutex.new
    @sequence = 0
    @connected = true
    @closed = false
  end

  attr_reader :sequence

  def connected?
    @connected
  end

  # Emite um evento do contrato: `event: <name>` + `data: <json>`.
  def emit(name, payload = {})
    raise Disconnected unless @connected

    @mutex.synchronize do
      @sequence += 1
      write_raw("id: #{@sequence}\nevent: #{name}\ndata: #{payload.to_json}\n\n")
    end
    true
  end

  # Comentario SSE: mantem a conexao viva sem virar evento para o cliente.
  def keep_alive
    raise Disconnected unless @connected

    @mutex.synchronize { write_raw(": keep-alive\n\n") }
    true
  end

  def start_heartbeat!
    return if @heartbeat_interval.blank? || @heartbeat_thread.present?

    @heartbeat_thread = Thread.new { heartbeat_loop }
  end

  def stop_heartbeat!
    @closed = true
    thread = @heartbeat_thread
    @heartbeat_thread = nil
    return if thread.blank?

    thread.kill
    thread.join(1)
  end

  def close
    stop_heartbeat!
    @mutex.synchronize do
      @stream.close
    rescue IOError, Errno::EPIPE
      nil
    end
  end

  private

  def heartbeat_loop
    loop do
      sleep @heartbeat_interval
      break if @closed || !@connected

      keep_alive
    end
  rescue Disconnected
    nil
  end

  def write_raw(payload)
    @stream.write(payload)
    true
  rescue *disconnect_errors
    @connected = false
    raise Disconnected
  end

  # ActionController::Live::ClientDisconnected so existe quando o Live esta
  # carregado; a lista e montada em runtime para o writer continuar testavel
  # com um IO qualquer.
  def disconnect_errors
    errors = [IOError, Errno::EPIPE, Errno::ECONNRESET]
    errors << ActionController::Live::ClientDisconnected if defined?(ActionController::Live::ClientDisconnected)
    errors
  end
end
