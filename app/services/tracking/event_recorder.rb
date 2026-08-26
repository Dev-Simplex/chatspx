# frozen_string_literal: true

# A porta de entrada do registro de eventos (bloco 5.03). Contrato em
# docs/tracking/contrato-de-eventos.md §5 — e as outras trilhas chamam DAQUI, nao do modelo:
# 5.04 (eventos do widget), 5.05 (event_id de volta ao widget), 5.16 (track() do site).
#
# `record!` e IDEMPOTENTE pela dedup_key. Registrar o mesmo fato duas vezes devolve o mesmo registro,
# sem criar nada e sem levantar erro — que e o comportamento de que o AsyncDispatcher precisa, porque
# `EventDispatcherJob.perform_later` e retentado quando falha. O `reporting_event_listener.rb:202-209`
# desta base documenta o mesmo risco e convive com ele; aqui o banco resolve.
class Tracking::EventRecorder
  class << self
    # A lista de campos nomeados E o contrato (docs/tracking/contrato-de-eventos.md §5). Trocar por um
    # hash opaco encurtaria a assinatura e pioraria exatamente a juncao que este bloco existe para
    # proteger: o consumidor deixaria de saber, pela propria chamada, o que pode mandar.
    # rubocop:disable Metrics/ParameterLists
    def record!(name:, account:, inbox: nil, conversation: nil, contact: nil,
                occurred_at: nil, properties: nil, source: :server, dedup_key: nil, deliver: true)
      # rubocop:enable Metrics/ParameterLists
      moment = occurred_at || Time.current
      key = dedup_key || TrackingEvent.derive_dedup_key(
        name: name, occurred_at: moment,
        conversation_id: conversation&.id, contact_id: contact&.id
      )

      event = create_or_find(name: name, account: account, inbox: inbox, conversation: conversation,
                             contact: contact, occurred_at: moment, properties: properties || {},
                             source: source, dedup_key: key)

      dispatch(event) if deliver
      event
    end

    private

    # Bloco 5.11 — o registro do fato e a unica porta por onde a fila server-side entra.
    #
    # ATUALIZADO em 26/08: o bloco 5.02 ATERRISSOU e a junta foi fechada, entao
    # `Tracking::CredentialResolver` nao devolve mais `nil` por construcao — ele le
    # `TrackingCredential` por (account_id, inbox_id). A fila anda quando ha credencial gravada e
    # segue inerte quando nao ha. O que mudou foi a RAZAO da inercia: antes nao havia com o que
    # falar; agora e ausencia de configuracao, que e o comportamento certo. O texto anterior
    # afirmava o oposto e teria enganado quem lesse este arquivo para decidir se podia ligar.
    #
    # O `rescue` segue a doutrina que o `TrackingEventListener` desta base ja escreveu: observabilidade
    # nunca quebra o produto. Falha ao ENTREGAR o evento nao pode desfazer o registro do fato nem
    # derrubar a resolucao de uma conversa.
    def dispatch(event)
      Tracking::DeliveryDispatcher.call(event)
    rescue StandardError => e
      ChatwootExceptionTracker.new(e, account: event.account).capture_exception
    end

    # O savepoint mantem a transacao externa viva quando o indice unico recusa a segunda gravacao:
    # no PostgreSQL, violacao de constraint aborta a transacao corrente, e sem `requires_new` o
    # chamador receberia o registro certo dentro de uma transacao que nao aceita mais nada.
    def create_or_find(attributes)
      TrackingEvent.transaction(requires_new: true) do
        TrackingEvent.create!(attributes)
      end
    rescue ActiveRecord::RecordNotUnique
      TrackingEvent.find_by!(account_id: attributes[:account].id, name: attributes[:name],
                             dedup_key: attributes[:dedup_key])
    end
  end
end
