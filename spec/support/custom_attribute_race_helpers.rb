# Ferramenta para reproduzir a corrida REAL do auto-provisionamento de
# CustomAttributeDefinition (bloco 1.16) — a que bate no indice unico, nao a que a validacao
# do Rails intercepta.
#
# Nao e incluido automaticamente: quem usa precisa desligar a fixture transacional
# (`self.use_transactional_tests = false`) e dar `include CustomAttributeRaceHelpers`. Com a
# fixture ligada existe uma conexao so — a linha da "outra requisicao" e visivel para o nosso
# SELECT, a validacao de unicidade barra antes do INSERT e o indice nunca entra na historia.
module CustomAttributeRaceHelpers
  # A OUTRA requisicao, em conexao propria: insere a mesma chave e SEGURA o commit ate ver
  # o nosso INSERT preso no indice. E o "segurar" que faz a diferenca: se ela commitasse
  # antes, o nosso SELECT de validacao veria a linha e o teste voltaria a medir a validacao.
  def concurrent_definition_holding(account:, key:, model: :contact_attribute)
    inserted = Queue.new
    release = Queue.new
    race_releases << release
    thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        CustomAttributeDefinition.transaction do
          CustomAttributeDefinition.create!(account_id: account.id, attribute_key: key, attribute_model: model,
                                            attribute_display_name: 'Outra requisicao', attribute_display_type: :text)
          inserted << :ok
          wait_until_our_insert_blocks(connection, release)
        end
      end
    rescue StandardError => e
      # Sem isto, um erro aqui deixaria o `pop` abaixo esperando para sempre e o teste
      # pareceria "lento" em vez de quebrado.
      inserted << e
    end
    race_threads << thread
    await_concurrent_insert(inserted, key)
    thread
  end

  # Libera as outras requisicoes e espera cada uma commitar. Tem de rodar ANTES de qualquer
  # limpeza: enquanto elas seguram o commit, a linha continua travada e um TRUNCATE ficaria
  # esperando ate o statement_timeout.
  def finish_concurrent_requests!
    race_releases.each { |release| release << :stop }
    race_threads.each { |thread| thread.join(30) }
  end

  # Sem fixture transacional nao ha rede de seguranca. `custom_attribute_definitions` nao tem
  # foreign key para `accounts` nesta base, entao truncar so `accounts CASCADE` deixaria as
  # definicoes para tras e contaminaria o exemplo seguinte.
  def truncate_all_tables!
    connection = ActiveRecord::Base.connection
    tables = connection.tables - %w[ar_internal_metadata schema_migrations]
    connection.execute("TRUNCATE TABLE #{tables.map { |table| connection.quote_table_name(table) }.join(', ')} CASCADE")
  end

  # Guarda contra o verde no vacuo: devolve o que aconteceu com cada INSERT que ESTA thread
  # tentou na tabela. Zero tentativas = a validacao do Rails barrou antes e o indice unico
  # nunca foi tocado — o teste teria passado sem medir o sujeito.
  def capture_definition_inserts
    attempts = []
    main = Thread.current
    subscription = ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
      next unless Thread.current == main

      event = ActiveSupport::Notifications::Event.new(*args)
      attempts << event.payload[:exception_object] if event.payload[:sql].to_s.start_with?('INSERT INTO "custom_attribute_definitions"')
    end
    yield
    attempts
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  private

  def race_threads
    @race_threads ||= []
  end

  def race_releases
    @race_releases ||= []
  end

  def await_concurrent_insert(inserted, key)
    signal = inserted.pop(timeout: 20)
    raise signal if signal.is_a?(StandardError)
    raise "a outra requisicao nao chegou a inserir #{key}" if signal.nil?
  end

  def wait_until_our_insert_blocks(connection, release, timeout: 10)
    # Controle negativo, para provar que a guarda de `capture_definition_inserts` nao passa
    # no vacuo: com CONTROLE_NEGATIVO=1 a outra requisicao commita antes da nossa validacao,
    # a colisao deixa de ser do indice e todo exemplo que use este helper falha em
    # `attempts` — nenhum consegue passar sem uma recusa real do indice unico.
    return if ENV['CONTROLE_NEGATIVO'] == '1'

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      break if release.size.positive?

      blocked = connection.select_value(<<~SQL.squish)
        SELECT count(*) FROM pg_stat_activity
        WHERE datname = current_database() AND pid <> pg_backend_pid()
          AND state = 'active' AND wait_event_type = 'Lock'
          AND query LIKE 'INSERT INTO "custom_attribute_definitions"%'
      SQL
      break if blocked.to_i.positive?
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.02
    end
  end
end
