# Extrai quadros de um video de anexo e os entrega como data URLs, prontos pra visao.
#
# Existe separado do Captain::MediaDescriptionService por dois motivos: e o unico ponto da
# camada que sai do processo (shell-out pro ffmpeg), e e o unico que depende de ferramenta
# instalada na VM — isolado, da pra testar e pra falhar sozinho sem levar a descricao junto.
#
# `ffmpeg` ja estava na frota (6.1.1 em /usr/bin/): e ele que o ActiveStorage usa pra
# analisar o blob, e por isso a duracao ja vem no metadata sem custo nenhum.
class Captain::VideoFrameExtractor
  # Comeco, meio e fim. Story costuma repetir o dado escrito em todas as cenas, entao mais
  # quadros pagam mais pelo mesmo texto.
  POSITIONS = [0.15, 0.5, 0.85].freeze
  WIDTH = 768
  FALLBACK_DURATION = 10.0

  # Um quadro de 768 px sai em menos de um segundo em qualquer video que este servico aceita
  # (o teto e 10 MB). O teto existe pro caso patologico, nao pro caso lento: sob pressao de
  # memoria do cgroup o ffmpeg entra em reclaim e para de progredir sem morrer e sem logar —
  # medido em homologacao com 6 processos parados ha 50 min, delta de CPU zero, segurando 15
  # das 17 threads do Sidekiq ate a fila `critical` acumular 47 min de latencia. Sem teto, um
  # quadro que nao progride custa uma thread para sempre.
  FFMPEG_TIMEOUT = ENV.fetch('CAPTAIN_FFMPEG_TIMEOUT', 60).to_i

  def initialize(attachment:)
    @attachment = attachment
  end

  # Devolve [] quando nao ha arquivo local, quando o ffmpeg nao existe ou quando ele falha —
  # nunca levanta. Os temporarios morrem antes de retornar.
  def data_urls
    return [] unless attachment.file.attached?

    dir = Rails.root.join('tmp/uploads/media-description', "att-#{attachment.id}")
    FileUtils.mkdir_p(dir)
    source = copy_source(dir)
    extract(dir, source).map { |path| "data:image/jpeg;base64,#{Base64.strict_encode64(File.binread(path))}" }
  rescue StandardError => e
    Rails.logger.error("[VideoFrames] FALHOU att=#{attachment&.id}: #{e.class}: #{e.message}")
    []
  ensure
    FileUtils.rm_rf(dir) if dir.present?
  end

  private

  attr_reader :attachment

  def copy_source(dir)
    blob = attachment.file.blob
    path = File.join(dir, "source#{File.extname(blob.filename.to_s).presence || '.mp4'}")
    File.open(path, 'wb') { |f| blob.open { |source| IO.copy_stream(source, f) } }
    path
  end

  def extract(dir, source)
    POSITIONS.each_with_index.filter_map do |position, index|
      out = File.join(dir, "frame-#{index}.jpg")
      ok = executar(source, out, position)
      next aviso(index) unless ok && File.exist?(out) && File.size(out).positive?

      out
    end
  end

  # `-nostdin` porque o irmao que ja roda em producao (EleventLabsTtsService) o usa: sem ele o
  # ffmpeg ainda tenta ler comandos interativos de um stdin que, num daemon, nunca fecha.
  # Devolve false — nunca levanta — para preservar o contrato de `extract`.
  def executar(source, out, position)
    pid = Process.spawn('ffmpeg', '-nostdin', '-loglevel', 'error', '-y',
                        '-ss', segundo(position).to_s, '-i', source,
                        '-frames:v', '1', '-vf', "scale=#{WIDTH}:-1", '-q:v', '4', out,
                        out: File::NULL, err: File::NULL)
    Timeout.timeout(FFMPEG_TIMEOUT) { Process.waitpid2(pid).last.success? }
  rescue Timeout::Error
    encerrar(pid)
    false
  rescue Errno::ENOENT
    false
  end

  # TERM primeiro, KILL se ele nao sair — e `detach` para o filho nao virar zumbi preso a esta
  # thread do Sidekiq, que e justamente o que este metodo existe pra soltar.
  def encerrar(pid)
    return if pid.blank?

    Process.kill('TERM', pid)
    sair = false
    10.times do
      break sair = true if Process.waitpid(pid, Process::WNOHANG)

      sleep 0.1
    end
    Process.kill('KILL', pid) unless sair
    Rails.logger.warn("[VideoFrames] ffmpeg excedeu #{FFMPEG_TIMEOUT}s e foi encerrado att=#{attachment&.id}")
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  ensure
    Process.detach(pid) if pid.present?
  end

  # A duracao vem do metadata que o ActiveStorage ja gravou; sem ela, um fallback curto
  # ainda pega o inicio do video.
  def segundo(position)
    duration = attachment.file.blob.metadata['duration'].to_f
    duration = FALLBACK_DURATION if duration <= 0
    (duration * position).round(1)
  end

  # `spawn` levanta Errno::ENOENT quando o binario nao existe, e o status vem falso quando ele
  # falha. Os dois casos sao configuracao de VM, nao incidente — mas precisam aparecer, senao o
  # operador liga a chave, nada acontece e nao ha o que olhar.
  def aviso(index)
    Rails.logger.warn("[VideoFrames] ffmpeg nao extraiu o quadro #{index} att=#{attachment&.id}")
    nil
  end
end
