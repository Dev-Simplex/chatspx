# frozen_string_literal: true

# Bloco 4.02 (BK-21) — "QUAL fluxo entregar", decidido no SERVIDOR.
#
# O widget nunca recebe a lista de fluxos nem os criterios: ele so recebe as MENSAGENS que o passo
# corrente produz. Este servico e quem escolhe, entre os fluxos `widget_prechat` ATIVOS da conta,
# o unico que atende esta conversa — por URL de origem, UTM, dispositivo, horario e inbox.
#
# A consulta usa o indice que ja existe: `index_flows_on_account_id_and_trigger_type_and_active`
# (account_id, trigger_type, active). O resto do casamento e em memoria, sobre o `trigger_config`
# jsonb — a cardinalidade e de dezenas de fluxos por conta, nao de milhares.
#
# O ALVO MORA NO `trigger_config` DO FLUXO, nao no `pre_chat_form_options` da inbox: um `flow_id`
# fixo por inbox contradiria de frente o aceite deste bloco ("dois fluxos ativos entregam fluxos
# diferentes conforme a URL") e criaria duas fontes de verdade para a mesma pergunta.
#
# Contrato completo (chave a chave, default e ausencia) em Flow::WidgetPrechatSchema e no relatorio
# plano/redesenho/execucao/o3-flows-captura.md §4.02.
class Flows::WidgetPrechatResolver
  # Regex de classificacao do dispositivo a partir do que o widget JA grava em
  # `conversation.additional_attributes['browser']` (device_name + platform_name). Tablet e
  # testado ANTES de mobile: um iPad casa os dois, e a categoria mais especifica vence.
  TABLET_SIGNATURE = /ipad|tablet|kindle|playbook|silk/i
  MOBILE_SIGNATURE = /iphone|ipod|android|blackberry|windows phone|mobile/i

  # Resolve a partir de uma conversa ja criada — o caminho de producao. A URL de origem e o
  # `referer` JA SANEADO pelo bloco 1.20 (Conversation#validate_referer_url).
  def self.for_conversation(conversation)
    return if conversation.blank?

    attributes = conversation.additional_attributes || {}
    new(account: conversation.account, inbox: conversation.inbox,
        url: attributes['referer'], browser: attributes['browser'])
  end

  def initialize(account:, inbox:, url: nil, browser: nil, at: nil)
    @account = account
    @inbox = inbox
    @url = url.to_s
    @browser = browser.is_a?(Hash) ? browser : {}
    @at = at || Time.current
  end

  # O fluxo escolhido, ou nil quando nenhum casa. Nunca levanta: um `trigger_config` torto de uma
  # conta nao pode derrubar a criacao da conversa de um visitante.
  def perform
    candidates.max_by { |flow| rank(flow) }
  rescue StandardError => e
    Rails.logger.error("Flows::WidgetPrechatResolver account=#{@account&.id} inbox=#{@inbox&.id}: #{e.message}")
    nil
  end

  private

  def candidates
    return [] if @account.blank? || @inbox.blank?
    return [] unless prechat_delegated_to_flow?

    @account.flows.active.widget_prechat.to_a.select { |flow| matches?(flow) }
  end

  # O fluxo de captura so e entregue quando a inbox DECLARA que o pre-chat dela E um fluxo.
  #
  # A guarda espelha a tela do bloco 3.14: em `PreChatPage.vue` o seletor de modos so aparece
  # DENTRO do interruptor mestre do pre-chat, e o modo `flow` grava
  # `pre_chat_form_options['mode'] = 'flow'` (vocabulario de Channel::WebWidget::PreChatFormSchema::MODES).
  # Sem ela, uma inbox no modo Simples rodaria o formulario classico E o fluxo — dois pre-chats
  # para o mesmo visitante, que e captura em duplicidade, nao redundancia inofensiva.
  #
  # `mode` ausente e o estado de TODA a frota hoje (a chave nasceu no 3.14): ausencia ⇒ nada muda.
  def prechat_delegated_to_flow?
    channel = @inbox.channel
    return false unless channel.respond_to?(:pre_chat_form_options)
    return false unless channel.pre_chat_form_enabled?

    channel.pre_chat_form_options.to_h['mode'].to_s == 'flow'
  end

  # DESEMPATE — a ordem esta publicada no contrato e e conferida por spec. `max_by` sobre a tupla:
  #   1. `priority` DESC          — o admin manda; e a unica alavanca explicita que ele tem.
  #   2. especificidade DESC      — nº de criterios DECLARADOS que casaram. Um catch-all (0
  #                                 criterios) sempre perde para um fluxo que fala daquela URL.
  #   3. id ASC (por -id)         — o MAIS ANTIGO vence. Criar um fluxo novo empatado nao rouba,
  #                                 em silencio, o trafego de um que ja estava no ar.
  def rank(flow)
    config = config_for(flow)
    # `.to_i` de proposito: `trigger_config` de fluxo antigo (ou escrito antes do schema) pode
    # trazer priority como String, e comparar String com Integer no max_by levantaria — o que,
    # pelo rescue do #perform, faria a conta INTEIRA parar de receber fluxo por causa de um.
    [config['priority'].to_i, specificity(config), -flow.id]
  end

  # Quantos criterios este fluxo DECLARA (e, por estar em `candidates`, casou). O catch-all
  # declara zero.
  def specificity(config)
    Array(config['url_conditions']).size +
      config['utm'].to_h.size +
      (Array(config['devices']).any? ? 1 : 0) +
      (config['business_hours_only'] ? 1 : 0)
  end

  def matches?(flow)
    config = config_for(flow)

    inbox_matches?(config) && url_matches?(config) && utm_matches?(config) &&
      device_matches?(config) && business_hours_match?(config)
  end

  # O `trigger_config` cru completado com os DEFAULTS publicados — assim todo o resto do servico
  # le chaves que sempre existem, e "o que acontece na ausencia" fica declarado num lugar so.
  def config_for(flow)
    raw = flow.trigger_config.is_a?(Hash) ? flow.trigger_config : {}
    Flow::WidgetPrechatSchema::DEFAULTS.merge(raw.slice(*Flow::WidgetPrechatSchema::DEFAULTS.keys).compact)
  end

  # `inbox_ids` vazio = vale para qualquer inbox Website da conta (o caso comum: uma inbox so).
  def inbox_matches?(config)
    ids = Array(config['inbox_ids'])
    ids.blank? || ids.map(&:to_i).include?(@inbox.id)
  end

  # Sem condicoes de URL o fluxo e catch-all — casa inclusive quando a conversa NAO tem referer
  # (visitante que chegou sem origem registrada continua recebendo o fluxo padrao da conta).
  def url_matches?(config)
    conditions = Array(config['url_conditions'])
    return true if conditions.blank?

    results = conditions.map { |condition| url_condition_matches?(condition) }
    config['match'] == 'any' ? results.any? : results.all?
  end

  # Comparacao case-insensitive sobre a URL INTEIRA (com querystring). URL ausente so casa
  # `not_contains` — nao ha texto onde procurar, entao "nao contem" e verdade e o resto e falso.
  def url_condition_matches?(condition)
    return false unless condition.is_a?(Hash)

    haystack = @url.downcase
    return condition['operator'] == 'not_contains' if haystack.blank?

    apply_url_operator(condition['operator'], haystack, condition['value'].to_s.downcase)
  end

  def apply_url_operator(operator, haystack, needle)
    case operator
    when 'contains' then haystack.include?(needle)
    when 'not_contains' then haystack.exclude?(needle)
    when 'equals' then haystack == needle
    when 'starts_with' then haystack.start_with?(needle)
    when 'ends_with' then haystack.end_with?(needle)
    else false
    end
  end

  # Todas as chaves de `utm` precisam bater (E), por igualdade case-insensitive, contra os
  # parametros da querystring da URL de origem. `utm` vazio nao filtra.
  def utm_matches?(config)
    wanted = config['utm'].to_h
    return true if wanted.blank?

    wanted.all? { |key, value| query_params[key.to_s.downcase] == value.to_s.downcase }
  end

  def query_params
    @query_params ||= parse_query_params
  end

  def parse_query_params
    return {} if @url.blank?

    query = URI.parse(@url).query
    return {} if query.blank?

    URI.decode_www_form(query).to_h { |key, value| [key.to_s.downcase, value.to_s.downcase] }
  rescue StandardError
    {} # URL que nem o saneamento do 1.20 recuperou: sem UTM legivel, o filtro simplesmente nao casa
  end

  # `devices` vazio nao filtra. Categoria desconhecida (browser nao gravado) nunca casa um filtro
  # declarado — preferimos NAO entregar um fluxo segmentado do que entregar o errado.
  def device_matches?(config)
    wanted = Array(config['devices'])
    return true if wanted.blank?

    wanted.include?(device_category)
  end

  def device_category
    @device_category ||= classify_device
  end

  def classify_device
    signature = [@browser['device_name'], @browser['platform_name']].compact.join(' ')
    return nil if signature.blank?
    return 'tablet' if signature.match?(TABLET_SIGNATURE)
    return 'mobile' if signature.match?(MOBILE_SIGNATURE)

    'desktop'
  end

  # `business_hours_only` respeita o MESMO expediente que o resto do produto (Inbox#working_now?,
  # concern OutOfOffisable). Inbox sem expediente configurado responde true — nao ha horario a
  # respeitar, e nao e papel deste servico inventar um.
  def business_hours_match?(config)
    return true unless config['business_hours_only']

    @inbox.working_now?
  end
end
