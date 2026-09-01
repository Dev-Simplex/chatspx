# frozen_string_literal: true

require 'rails_helper'

# `require: false` no Gemfile: a gem só entra no boot quando `SENTRY_DSN` existe
# (`config/application.rb:24`). Carregar aqui à mão é o que torna este arquivo
# DETERMINÍSTICO — ele mede o código, não a máquina. Sem esta linha, o arquivo
# passaria numa VM com DSN e explodiria com `NameError` na VM ao lado.
require 'sentry-ruby'

# Mecanismo de aceite do bloco 2.13 — a PRIMEIRA metade, medida SEM DUBLÊ.
#
# ACEITE (§2.2): «Erro forçado aparece no GlitchTip **com PII removida**».
#
# ── POR QUE ESTE ARQUIVO EXISTE, SENDO QUE JÁ HAVIA UM ───────────────────────
#
# `error_report_spec.rb` monta `stub_const('Sentry', double(...))`. Um duplo
# recebe `with_scope`, `set_tags`, `set_context` e `capture_message` e devolve
# `nil` — ele NUNCA CONSTRÓI O EVENTO. E é justamente na construção do evento
# que a PII entrava:
#
#   `Sentry::Rack::CaptureExceptions` guarda o rack env inteiro no escopo de
#   cada requisição; `Sentry.with_scope` duplica esse escopo; e
#   `Scope#apply_to_event` faz `event.rack_env = rack_env`, o que — com
#   `send_default_pii = true`, que é o que está em
#   `config/initializers/sentry.rb:14` — publica `cookies`, `query_string`, o
#   corpo do POST, os cabeçalhos (inclusive `Referer`) e `user[:ip_address]`.
#
# Ou seja: o arquivo com duplo ficava VERDE enquanto o evento real saía levando
# o cookie `cw_conversation` — o JWT que dá acesso de leitura à conversa daquele
# visitante — para um agregador de erros externo. É por isso que aqui o SDK é o
# de verdade, com `DummyTransport` no lugar da rede: o que se inspeciona é o
# evento QUE IRIA PARA O FIO.
#
# ── O CONTROLE POSITIVO NÃO É ENFEITE ────────────────────────────────────────
#
# Toda asserção deste arquivo é NEGATIVA («não contém o cookie», «não tem IP»),
# e asserção negativa passa também quando o sujeito nunca existiu — bastaria o
# rack env não chegar ao escopo para tudo ficar verde medindo NADA. Por isso o
# primeiro exemplo captura um evento pelo caminho CRU, sem passar pelo serviço,
# e exige VER o cookie, o `Referer` com o JWT e o IP. Ele é o que prova que a
# bancada enxerga o vazamento — e é ele que ficaria vermelho se um dia o SDK
# parasse de anexar a requisição e os outros exemplos virassem decoração.
RSpec.describe Widget::ErrorReport do
  # O título do arquivo mora aqui e não no segundo argumento do `describe`: o
  # rubocop reserva aquele lugar para o método sob teste (`RSpec/DescribeMethod`).
  #
  # SEM DUBLÊ DE `Sentry` — é isso que separa este arquivo do vizinho.
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }

  # Um JWT com a forma real do `cw_conversation`: três segmentos base64url. É
  # ele que o `Widget::TokenService` emite e que o cookie carrega.
  let(:jwt_da_conversa) do
    'eyJhbGciOiJIUzI1NiJ9.eyJzb3VyY2VfaWQiOiJhYmMiLCJpbmJveF9pZCI6N30.assinatura-falsa'
  end
  let(:ip_do_visitante) { '203.0.113.7' }

  # O MESMO rack env que a requisição real produz: o widget faz `POST` para
  # `/api/v1/widget/telemetry` a partir do documento
  # `/widget?website_token=…&cw_conversation=<JWT>`, então o `Referer` carrega o
  # JWT na query e o cabeçalho `Cookie` o carrega de novo.
  let(:rack_env) do
    Rack::MockRequest.env_for(
      'https://painel.chatspx.test/api/v1/widget/telemetry',
      method: 'POST',
      input: '{"name":"TypeError","message":"x"}'
    ).merge(
      'CONTENT_TYPE' => 'application/json',
      'HTTP_COOKIE' => "cw_conversation=#{jwt_da_conversa}; _chatwoot_session=sessao-do-painel",
      'HTTP_REFERER' => "https://painel.chatspx.test/widget?website_token=abc&cw_conversation=#{jwt_da_conversa}",
      'HTTP_USER_AGENT' => 'Mozilla/5.0',
      'REMOTE_ADDR' => ip_do_visitante
    )
  end

  let(:transporte) { Sentry.get_current_client.transport }
  # Só o evento do widget: o controle positivo é capturado num exemplo próprio.
  let(:evento) { transporte.events.last }

  around do |exemplo|
    hub_anterior = Sentry.get_main_hub
    worker_anterior = Sentry.instance_variable_get(:@background_worker)

    Sentry.init do |config|
      # DSN sintético e `DummyTransport`: nada sai desta máquina. Disparar
      # evento de teste contra o GlitchTip de produção poluiria a triagem real
      # da frota inteira.
      config.dsn = 'http://0123456789abcdef0123456789abcdef@localhost:9/42'
      config.transport.transport_class = Sentry::DummyTransport
      config.environment = 'test'
      config.enabled_environments = %w[test]
      # ESTA LINHA É O PONTO. É a configuração de produção
      # (`config/initializers/sentry.rb:14`) reproduzida aqui de propósito: com
      # ela desligada, o SDK já removeria cookies e IP sozinho e o arquivo
      # inteiro mediria zero.
      config.send_default_pii = true
      # Sem fila: `capture_event` chama `send_event` na mesma thread, então
      # `transporte.events` está pronto assim que `perform` retorna.
      config.background_worker_threads = 0
      config.release = 'servidor-sem-widget'
    end

    exemplo.run
  ensure
    Sentry.instance_variable_set(:@main_hub, hub_anterior)
    Sentry.instance_variable_set(:@background_worker, worker_anterior)
    Thread.current.thread_variable_set(Sentry::THREAD_LOCAL, hub_anterior)
  end

  before do
    # EXATAMENTE o que `Sentry::Rack::CaptureExceptions#call` faz em toda
    # requisição (`sentry-ruby-5.19.0/lib/sentry/rack/capture_exceptions.rb:23`).
    # Não é simulação de conveniência: é a mesma chamada, com um env construído
    # pelo `Rack::MockRequest`.
    Sentry.get_current_scope.set_rack_env(rack_env)
  end

  def relatar(payload)
    described_class.new(payload.with_indifferent_access, web_widget).perform
  end

  # O evento SERIALIZADO, menos a interface `threads`.
  #
  # A exclusão é nomeada e tem motivo, não é conveniência: `Client#event_from_message`
  # SEMPRE anexa `threads` com o backtrace do ponto de chamada — e o `StacktraceBuilder`
  # lê do disco o CÓDIGO-FONTE em volta de cada quadro (`pre_context`/`post_context`).
  # Em produção esses quadros são `error_report.rb`, o controller e as gems: código
  # nosso, nunca dado de visitante. Aqui um dos quadros é ESTE ARQUIVO, cujas linhas
  # carregam os literais de PII falsa que os exemplos usam — sem a exclusão, o exemplo
  # falharia encontrando a fonte do próprio teste, e não um vazamento.
  #
  # O que sobra é onde a PII de verdade entraria: `request` (cookies, `Referer`, corpo,
  # query), `user` (IP), `message`, `tags` e `contexts`. Foi medido: com o serviço sem
  # `set_rack_env({})` os três primeiros exemplos abaixo reprovam nesta mesma string.
  def texto_do_evento
    evento.to_hash.except(:threads).to_json
  end

  describe 'CONTROLE — a bancada enxerga o vazamento' do
    it 'um evento capturado pelo caminho cru leva cookie, Referer e IP' do
      # Sem o serviço no meio: é o que o `Sentry.capture_message` de qualquer
      # lugar do código produz com o escopo desta requisição. Se este exemplo
      # ficar verde sem ver a PII, todos os outros deste arquivo passaram a
      # medir nada — e é este que fica vermelho para avisar.
      Sentry.with_scope { Sentry.capture_message('controle', level: :error) }

      cru = transporte.events.last.to_hash

      expect(cru[:request][:cookies]['cw_conversation']).to eq(jwt_da_conversa)
      expect(cru[:request][:headers]['Referer']).to include(jwt_da_conversa)
      expect(cru[:user][:ip_address]).to eq(ip_do_visitante)
    end
  end

  describe 'o evento do widget' do
    before { relatar(name: 'TypeError', message: 'falhou', context: { origem: 'store/conversation' }) }

    it 'não tem interface de requisição nenhuma' do
      expect(evento.to_hash).not_to have_key(:request)
    end

    it 'não leva o JWT de conversa, nem por cookie nem por Referer' do
      # Medido no evento SERIALIZADO — é o texto que iria para o fio, e não uma
      # travessia de campos escolhidos a dedo que deixaria escapar um caminho
      # novo (o `env`, por exemplo).
      expect(texto_do_evento).not_to include(jwt_da_conversa)
      expect(texto_do_evento).not_to include('cw_conversation')
    end

    it 'não leva o IP do visitante' do
      expect(evento.to_hash[:user]).to eq({})
      expect(texto_do_evento).not_to include(ip_do_visitante)
    end

    it 'ainda leva o que serve para triagem' do
      # A outra metade do erro seria raspar tudo e mandar um evento inútil.
      expect(evento.to_hash[:message]).to eq('[widget] TypeError: falhou')
      expect(evento.to_hash[:tags]).to include(source: 'web_widget', origem: 'store/conversation')
      expect(evento.to_hash[:tags]).to include(account_id: web_widget.inbox.account_id)
    end
  end

  describe 'a raspagem de PII, agora no evento real' do
    it 'a mensagem chega ao evento já sem e-mail, telefone e documento' do
      relatar(
        name: 'Error',
        message: 'falha ao enviar para maria.silva@empresa.com.br, tel +55 11 98765-4321, cpf 123.456.789-09',
        stack: 'at envia (https://loja.test/x?token=abcdef123456:1:1)',
        context: { origem: 'store/message' }
      )

      texto = texto_do_evento

      expect(texto).not_to include('maria.silva@empresa.com.br')
      expect(texto).not_to include('98765-4321')
      expect(texto).not_to include('123.456.789-09')
      expect(texto).not_to include('abcdef123456')
      expect(evento.to_hash[:message]).to include('[email]', '[telefone]', '[documento]')
    end
  end

  describe 'release' do
    it 'o release que o widget informa vira o `release` DO EVENTO' do
      # Antes deste bloco, `release` existia no envelope e morria no contexto: o
      # GlitchTip agrupa e filtra pelo campo de topo, não por uma chave dentro
      # de um contexto. E o servidor nunca o publicava, então chegava `null` em
      # toda instalação — só o harness de E2E o fabricava.
      relatar(name: 'Error', message: 'x', release: '4.16.2', context: { origem: 'chat' })

      expect(evento.to_hash[:release]).to eq('4.16.2')
    end

    it 'sem release do widget, o do servidor continua valendo' do
      relatar(name: 'Error', message: 'x', context: { origem: 'chat' })

      expect(evento.to_hash[:release]).to eq('servidor-sem-widget')
    end

    it 'o release do cliente é texto de fora: raspado e cortado' do
      relatar(name: 'Error', message: 'x', release: "v1 #{'a' * 400}", context: { origem: 'chat' })

      expect(evento.to_hash[:release].length).to eq(Widget::ErrorReport::LIMITE_RELEASE)
    end
  end
end
