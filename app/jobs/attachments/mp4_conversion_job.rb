# Troca o .MOV de um video (enviado pelo atendente ou recebido do cliente) por um .mp4 (Video::Mp4Converter).
#
# No envio, enquanto este job nao termina, a mensagem espera (Attachment#aguardando_mp4?): o
# SendReplyJob e o webhook da caixa API (ponte da WAHA) voltam a olhar a cada poucos segundos.
# Quando a conversao falha, o anexo fica marcado e o envio segue com o arquivo original.
class Attachments::Mp4ConversionJob < ApplicationJob
  queue_as :medium
  # O upload do arquivo pode terminar depois que o job comeca (o mesmo motivo da espera do
  # SendReplyJob em Message#send_reply).
  retry_on ActiveStorage::FileNotFoundError, wait: 3.seconds, attempts: 5 do |job, _error|
    attachment = Attachment.find_by(id: job.arguments.first)
    Attachments::MetaMerge.call(attachment, 'mp4' => 'falhou') if attachment
  end

  # Uma conversao por vez na VM: o ffmpeg divide o teto de memoria do worker (Video::Mp4Converter#decoder_args).
  LOCK_KEY = "MP4_CONVERSION_LOCK::#{Socket.gethostname}".freeze
  LOCK_TTL = Video::Mp4Converter::TIMEOUT_SECONDS + 60
  BUSY_WAIT = 10.seconds
  # O pico medido de um 4K HEVC e ~360 MB.
  MEMORY_NEEDED = 500.megabytes

  def perform(attachment_id)
    attachment = Attachment.find_by(id: attachment_id)
    return unless attachment&.converter_mp4?

    lock_manager = Redis::LockManager.new
    return self.class.set(wait: BUSY_WAIT).perform_later(attachment_id) unless lock_manager.lock(LOCK_KEY, LOCK_TTL)

    begin
      run(attachment)
    ensure
      lock_manager.unlock(LOCK_KEY)
    end
  end

  private

  def run(attachment)
    if !free_memory?
      Rails.logger.warn("[Attachments::Mp4ConversionJob] sem memoria livre no worker, segue o original att=#{attachment.id}")
      Attachments::MetaMerge.call(attachment, 'mp4' => 'falhou')
    elsif convert(attachment)
      refresh_bubble(attachment)
    else
      Attachments::MetaMerge.call(attachment, 'mp4' => 'falhou')
    end
  end

  # Folga ate o teto do cgroup do worker (memory.max - uso que nao e cache de arquivo). Fora de um
  # cgroup com teto (dev, Docker sem limite), nao ha o que conferir.
  def free_memory?
    dir = "/sys/fs/cgroup#{File.read('/proc/self/cgroup')[/^0::(.*)$/, 1]}"
    max = File.read("#{dir}/memory.max").strip
    return true if max == 'max'

    used = File.read("#{dir}/memory.current").to_i - File.read("#{dir}/memory.stat")[/^inactive_file (\d+)/, 1].to_i
    max.to_i - used >= MEMORY_NEEDED
  rescue SystemCallError
    true
  end

  def convert(attachment)
    Dir.mktmpdir('mp4-conversion') do |dir|
      source = File.join(dir, 'source.mov')
      output = File.join(dir, 'video.mp4')
      attachment.file.blob.open { |file| FileUtils.cp(file.path, source) }
      next false unless Video::Mp4Converter.new(source).convert(output)

      # Vira :video tambem quando o navegador mandou o .MOV sem tipo e ele entrou como :file. O `save`
      # e explicito (com o file_type mudado, o `attach` nao salva sozinho) e fica dentro do bloco: o upload
      # roda no commit e le o arquivo aberto. Um .mp4 acima do limite da caixa nao passa na validacao, o
      # save devolve false e o envio segue com o original.
      attachment.file_type = :video
      File.open(output) do |io|
        attachment.file.attach(io: io, filename: "#{attachment.file.filename.base}.mp4", content_type: 'video/mp4')
        attachment.save
      end
    end
  rescue ActiveStorage::FileNotFoundError
    raise
  rescue StandardError => e
    Rails.logger.error("[Attachments::Mp4ConversionJob] FALHOU att=#{attachment.id}: #{e.class}: #{e.message}")
    false
  end

  # So a tela: no envio, o webhook `message_created` da caixa API ainda vai sair (ja com o .mp4), e um
  # `message_updated` antes dele chegaria a ponte da WAHA fora de ordem.
  def refresh_bubble(attachment)
    message = attachment.message.reload
    ActionCableListener.instance.message_updated(Events::Base.new(::Events::Types::MESSAGE_UPDATED, Time.zone.now, message: message))
  end
end
