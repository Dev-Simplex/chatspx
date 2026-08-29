require 'rails_helper'

RSpec.describe Captain::VideoFrameExtractor, type: :service do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, conversation: conversation, account: account, message_type: :incoming) }
  let(:attachment) do
    a = message.attachments.create!(account: account, file_type: :video)
    a.file.attach(io: StringIO.new('nao-e-um-mp4-de-verdade'), filename: 'v.mp4', content_type: 'video/mp4')
    a
  end

  describe 'o teto de tempo do shell-out' do
    # Este e o exemplo que existe por causa do incidente: um ffmpeg que NAO progride segurava a
    # thread do Sidekiq para sempre. Ele so passa se houver teto — sem o teto, o `sleep` abaixo
    # roda ate o fim e o exemplo estoura o proprio limite.
    it 'encerra o processo e devolve [] quando o ffmpeg nao termina' do
      stub_const("#{described_class}::FFMPEG_TIMEOUT", 1)
      original = Process.method(:spawn)
      pids = []
      allow(Process).to receive(:spawn) do |*_args, **_opts|
        pid = original.call('sleep', '120', out: File::NULL, err: File::NULL)
        pids << pid
        pid
      end

      resultado = nil
      decorrido = Benchmark.realtime { resultado = described_class.new(attachment: attachment).data_urls }

      # Sem esta linha o exemplo passa no vacuo: um codigo que nem chame `Process.spawn` tambem
      # devolve [] rapido, e o teto nunca seria exercitado.
      expect(Process).to have_received(:spawn).at_least(:once)
      expect(resultado).to eq([])
      expect(decorrido).to be < 30, "levou #{decorrido.round(1)}s — o teto de 1s por quadro nao foi aplicado"

      # e o filho nao pode ficar vivo depois: era ele que segurava a thread.
      sobreviventes = pids.select { |pid| File.exist?("/proc/#{pid}") && File.read("/proc/#{pid}/stat").split[2] != 'Z' }
      expect(sobreviventes).to be_empty, "ffmpeg #{sobreviventes.inspect} continua vivo apos o teto"
    end

    # Anti-vacuo: se o dublê nunca for chamado, o exemplo de cima passa por ausencia de sujeito.
    it 'chama mesmo o ffmpeg uma vez por posicao' do
      original = Process.method(:spawn)
      allow(Process).to receive(:spawn) { |*_a, **_k| original.call('true', out: File::NULL, err: File::NULL) }
      described_class.new(attachment: attachment).data_urls
      expect(Process).to have_received(:spawn).exactly(described_class::POSITIONS.size).times
    end

    it 'passa -nostdin, como o irmao que ja roda em producao' do
      original = Process.method(:spawn)
      allow(Process).to receive(:spawn) { |*_a, **_k| original.call('true', out: File::NULL, err: File::NULL) }
      described_class.new(attachment: attachment).data_urls
      expect(Process).to have_received(:spawn).with('ffmpeg', '-nostdin', *any_args).at_least(:once)
    end

    it 'devolve [] sem levantar quando o binario nao existe' do
      allow(Process).to receive(:spawn).and_raise(Errno::ENOENT)
      expect { described_class.new(attachment: attachment).data_urls }.not_to raise_error
      expect(described_class.new(attachment: attachment).data_urls).to eq([])
    end
  end

  describe 'o pool que o video pode ocupar' do
    # O Sidekiq roda o arquivo por ERB antes de parsear; renderizar aqui tambem prova que o
    # ERB da capsula e valido. As chaves com dois-pontos viram SIMBOLO no Psych.
    let(:yml) do
      YAML.load(ERB.new(File.read(Rails.root.join('config/sidekiq.yml'))).result, aliases: true)
    end

    it 'manda a descricao de midia para uma fila fora do pool principal' do
      expect(Captain::MediaDescriptionJob.new.queue_name).to eq('media_processing')
      expect(yml[:queues]).to be_present, 'nao achei a lista de filas: o spec esta medindo nada'
      expect(yml[:queues]).not_to include('media_processing'),
                                  'a fila esta no pool principal: a capsula nao limita nada'
    end

    it 'da a essa fila uma capsula com pool menor que o principal' do
      media = (yml[:capsules] || {})['media']
      expect(media).to be_present, 'sem capsula `media` o video volta a competir pelas 17 threads'
      expect(media[:queues]).to include('media_processing')
      expect(media[:concurrency].to_i).to be > 0
      expect(media[:concurrency].to_i).to be < yml[:concurrency].to_i,
                                          "capsula com #{media[:concurrency]} threads nao limita nada diante de #{yml[:concurrency]}"
    end
  end
end
