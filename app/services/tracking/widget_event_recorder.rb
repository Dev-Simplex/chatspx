# frozen_string_literal: true

# Blocos 5.05 e 5.16 — o registro dos eventos que chegam pelo endpoint do widget.
#
# ── POR QUE ESTE ARQUIVO EXISTE, E NÃO É MAIS UM LISTENER ────────────────────────────────────
#
# O aceite do 5.05 é "`event_id` nasce no backend e VOLTA AO WIDGET". Voltar exige que o id exista
# quando a resposta é montada — ou seja, no ciclo da requisição. Um listener roda depois, dentro do
# `EventDispatcherJob`, e o controller já teria respondido.
#
# ── A ARMADILHA QUE ELE CONSOME, EM VEZ DE CONTORNAR ─────────────────────────────────────────
#
# O `EventDispatcherJob` é RETENTADO. Sem idempotência do FATO, o segundo pouso do mesmo evento
# criaria um registro novo com `event_id` novo — e o índice único de (evento, destino), que é a
# trava de entrega dupla do 5.03, não tocaria em nada: para o banco seriam dois eventos diferentes.
# A trava certa está uma camada acima, em (`account_id`, `name`, `dedup_key`), e a forma de
# consumi-la é passar uma `dedup_key` PRESA AO SUJEITO do fato, nunca ao relógio (contrato §4.2).
#
# Aqui o registro é síncrono e o job não o recria, mas a mesma trava protege do que ESTE caminho
# tem de repetição: o widget reenvia `webwidget.triggered` a cada abertura da bolha — o visitante
# que abre, fecha e reabre três vezes é um fato só, não três conversões.
#
# ── O QUE ELE NÃO INVENTA ───────────────────────────────────────────────────────────────────
#
# O vocabulário é o de `docs/tracking/contrato-de-eventos.md`. `campaign.triggered` não aparece no
# mapa da §1 porque campanha exibida **não tem** contrapartida no vocabulário de tracking — e a
# ausência é declarada, não esquecimento (o mesmo `tracking: null` que `SDK_EVENT_CONTRACT` guarda
# no lado do widget). Registrar um `chatspx_campaign_shown` aqui seria acertar com a outra ponta um
# evento que o contrato não tem.
class Tracking::WidgetEventRecorder
  # Os nomes do barramento interno que TÊM contrapartida no vocabulário de tracking (contrato §1).
  # O barramento continua recebendo todos — este mapa só decide quais viram registro de tracking.
  LEGACY_TO_TRACKING = {
    Events::Types::WEBWIDGET_TRIGGERED => 'chatspx_widget_opened'
  }.freeze

  # O prefixo do contrato (§1, regra 1). É por ele que o controller distingue o evento do
  # barramento interno (`webwidget.triggered`) do evento de tracking que o site do cliente emite
  # por `track()` — dois vocabulários, um endpoint.
  TRACKING_PREFIX = TrackingEvent::NAME_PREFIX

  class << self
    def tracking_name?(name)
      name.to_s.start_with?(TRACKING_PREFIX)
    end

    # 5.05 — o evento do widget. NUNCA levanta: `webwidget.triggered` já funcionava antes deste
    # bloco e continua funcionando se o registro falhar. Observabilidade não quebra o produto —
    # é a mesma doutrina do `TrackingEventListener`.
    def record_legacy(contact_inbox:, name:, event_info: {}, occurred_at: nil)
      tracking_name = LEGACY_TO_TRACKING[name.to_s]
      return nil if tracking_name.blank?

      record!(
        contact_inbox: contact_inbox,
        name: tracking_name,
        properties: legacy_properties(contact_inbox, event_info),
        source: :widget,
        occurred_at: occurred_at,
        # A CHAVE NATURAL: o sujeito do fato é o visitante nesta inbox, não o instante. Abrir a
        # bolha cinco vezes na mesma sessão é uma pessoa que abriu o chat, e o registro devolvido
        # é o MESMO — com o mesmo `event_id`, que é o que a resposta leva de volta ao widget.
        dedup_key: "#{tracking_name}:contact_inbox:#{contact_inbox.id}"
      )
    rescue StandardError => e
      ChatwootExceptionTracker.new(e, account: contact_inbox&.inbox&.account).capture_exception
      nil
    end

    # 5.16 — o evento próprio do site, vindo de `window.$chatwoot.track()`.
    #
    # Aqui a exceção SOBE de propósito, e a diferença com o caminho acima é o público: ali quem
    # dispara é o nosso widget e o visitante não pode pagar pelo nosso defeito; aqui quem dispara é
    # o integrador, e um nome fora do contrato ou uma chave de PII em `properties` tem de voltar
    # como 422 nomeando a regra violada. Recusa silenciosa faria o integrador achar que integrou.
    def record_site_event!(contact_inbox:, name:, properties: {}, occurred_at: nil)
      record!(
        contact_inbox: contact_inbox,
        name: name,
        properties: properties || {},
        source: :site,
        occurred_at: occurred_at,
        # Sem chave natural: só o site sabe o que é "o mesmo pedido de orçamento". A derivação do
        # contrato (§4.2) usa `occurred_at.to_i`, o que resolve o reenvio da mesma chamada e não
        # distingue dois disparos genuínos no mesmo segundo — que, para um evento disparado por
        # clique, é justamente o comportamento desejado.
        dedup_key: nil
      )
    end

    private

    # Mesma razao do `Tracking::EventRecorder.record!`: a lista de campos nomeados E o contrato.
    # Um hash opaco encurtaria a assinatura e faria o chamador deixar de saber, pela propria
    # chamada, o que ele pode mandar.
    # rubocop:disable Metrics/ParameterLists
    def record!(contact_inbox:, name:, properties:, source:, occurred_at:, dedup_key:)
      # rubocop:enable Metrics/ParameterLists
      inbox = contact_inbox.inbox

      Tracking::EventRecorder.record!(
        name: name,
        account: inbox.account,
        inbox: inbox,
        conversation: last_conversation(contact_inbox),
        contact: contact_inbox.contact,
        occurred_at: occurred_at || Time.current,
        properties: properties,
        source: source,
        dedup_key: dedup_key
      )
    end

    # `default_scope` de `Message` inverte `order` — em `Conversation` não há esse problema, mas a
    # ordenação é explícita pelo mesmo motivo que no `TrackingEventListener`: "a última" precisa
    # ser a última por um critério escrito, não pelo que o banco devolver.
    def last_conversation(contact_inbox)
      contact_inbox.conversations.order(created_at: :desc).first
    end

    # Os parâmetros que o contrato declara para o evento #2 (`inbox_id`, `page_url`).
    #
    # `page_url` sai SEM query string, e isso não é arredondamento: a query é onde mora o e-mail
    # que um formulário do site colocou na URL, e `properties` alimenta o `dataLayer` e os params
    # do `fbq`/`gtag` (regra RC5). O `TrackingEvent` recusa chave de PII; ele não tem como recusar
    # um e-mail escondido dentro de uma URL. Mesma decisão do `landing_page` do bloco 5.08.
    def legacy_properties(contact_inbox, event_info)
      {
        'inbox_id' => contact_inbox.inbox_id,
        'page_url' => sanitized_page_url(event_info)
      }.compact
    end

    def sanitized_page_url(event_info)
      bruto = (event_info || {}).with_indifferent_access[:referer]
      return nil if bruto.blank?

      uri = URI.parse(bruto.to_s)
      return nil if uri.host.blank?

      "#{uri.scheme}://#{uri.host}#{uri.path}"
    rescue URI::InvalidURIError
      nil
    end
  end
end
