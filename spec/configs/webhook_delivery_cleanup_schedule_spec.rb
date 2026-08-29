require 'rails_helper'
require 'fugit'

# Bloco 4.14 — a retencao de 7 dias so acontece se alguem CHAMAR o job.
#
# O `Webhooks::DeliveryCleanupJob` existia, tinha spec proprio e passava verde sem nunca ter
# sido enfileirado uma vez: o unico chamador era o `perform_now` do proprio teste. Um job que
# so roda dentro do teste que o testa e um job que nao roda — e a tabela `webhook_deliveries`
# crescia sem teto na frota enquanto a suite dizia que a retencao funcionava.
#
# Estes exemplos existem para que APAGAR a entrada do `config/schedule.yml` fique VERMELHO.
# Sem eles, remover o agendamento nao quebra teste nenhum: o `spec/configs/schedule_spec.rb`
# so procura chave duplicada, e o spec de retencao chama o job na mao.
# `context` e nao `describe`, como no `spec/configs/schedule_spec.rb` vizinho: o sujeito aqui e
# o arquivo de configuracao, nao uma classe.
RSpec.context 'with Webhooks::DeliveryCleanupJob scheduled' do
  # O MESMO caminho de leitura do `config/initializers/sidekiq.rb:39`. Ler o arquivo por outro
  # meio mediria um arquivo que a producao nao carrega.
  let(:schedule) { YAML.load_file(Rails.root.join('config/schedule.yml')) }
  # O nome sai da propria classe: renomear o job e nao mexer no YAML fica vermelho.
  let(:job) { Webhooks::DeliveryCleanupJob }
  let(:classe) { job.name }
  let(:entradas) { schedule.select { |_chave, valor| valor['class'] == classe } }
  let(:entrada) { entradas.values.first || {} }

  it 'tem UMA entrada no schedule.yml apontando para o job de limpeza' do
    expect(entradas.size).to eq(1),
                             "esperava 1 entrada com class: #{classe} em config/schedule.yml, achei #{entradas.size}. " \
                             'Sem ela o job nunca e enfileirado e a retencao de 7 dias nao acontece.'
  end

  # O cruzamento que o `load_from_hash` nao faz: ele aceita nome de classe inexistente em
  # silencio (`get_job_options` devolve {"queue"=>"default"} e segue). Um rename do job
  # deixaria a entrada no arquivo apontando para o vazio, e nada ficaria vermelho.
  it 'o nome no schedule.yml resolve para um ActiveJob de verdade' do
    resolvida = entrada['class'].to_s.safe_constantize

    expect(resolvida).to be_present, "#{entrada['class'].inspect} esta no schedule.yml e nao existe no codigo"
    expect(resolvida.ancestors).to include(ActiveJob::Base)
    expect(resolvida.instance_method(:perform).arity).to eq(0),
                                                         'o cron enfileira sem argumentos; um perform que exige parametro estoura na fila'
  end

  # sidekiq-cron 2.4.0, job.rb:174: `klass_const.set(queue: @queue).perform_later`. A fila do
  # schedule VENCE o `queue_as` da classe. Se as duas divergirem, ler a classe mente sobre
  # onde o job roda — e foi lendo `queue_as` que se decidiu a prioridade dele.
  it 'a fila do schedule concorda com o queue_as da classe' do
    expect(entrada['queue']).to eq(job.new.queue_name)
  end

  # Fila fora do `config/sidekiq.yml` nao tem consumidor: o job seria enfileirado todo dia e
  # ficaria parado para sempre, que e o mesmo resultado de nao agendar.
  it 'a fila e consumida por algum worker do sidekiq.yml' do
    filas = YAML.safe_load(File.read(Rails.root.join('config/sidekiq.yml')),
                           permitted_classes: [Symbol], aliases: true)[:queues]

    expect(filas).to include(entrada['queue'])
  end

  # Retencao de 7 dias com cron semanal deixaria a linha viver ate 14 dias. O que importa nao
  # e a string do cron, e o intervalo REAL entre dois disparos — medido, nao lido.
  it 'dispara com folga dentro da janela de retencao' do
    cron = Fugit.parse_cron(entrada['cron'].to_s)
    expect(cron).to be_present, "cron invalido: #{entrada['cron'].inspect}"

    inicio = Time.utc(2026, 1, 1)
    disparos = 15.times.reduce([inicio]) { |acc, _| acc << cron.next_time(acc.last).to_t }
    maior_intervalo = disparos.each_cons(2).map { |anterior, seguinte| seguinte - anterior }.max

    expect(maior_intervalo).to be <= 1.day,
                               "o maior intervalo entre disparos e #{(maior_intervalo / 3600).round}h; " \
                               "com retencao de #{WebhookDelivery::RETENTION.inspect} a linha viveria alem da janela"
  end

  # A ponta funcional: quem esta AGENDADO e quem apaga. Constantizar o nome lido do arquivo
  # amarra as duas coisas — apontar a entrada para outra classe fica vermelho aqui.
  it 'o que o schedule.yml agenda realmente apaga o que passou de 7 dias' do
    account = create(:account)
    webhook = create(:webhook, account: account, url: 'https://destino.exemplo.com/h',
                               subscriptions: ['conversation_created'])
    velha = create(:webhook_delivery, webhook: webhook, account: account, delivery_id: 'velha')
    nova = create(:webhook_delivery, webhook: webhook, account: account, delivery_id: 'nova')
    velha.update_columns(created_at: (WebhookDelivery::RETENTION + 1.day).ago) # rubocop:disable Rails/SkipsModelValidations

    entrada['class'].to_s.constantize.perform_now

    expect(WebhookDelivery.exists?(velha.id)).to be(false)
    expect(WebhookDelivery.exists?(nova.id)).to be(true)
  end
end
