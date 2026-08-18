# frozen_string_literal: true

# Bloco 1.19 — parser de origem (C0), **prospectivo por decisão de produto (D6)**.
#
# Entrada: a URL que o widget manda em `message[referer_url]`, já saneada pelo 1.20.
# Saída: um hash de chaves BASE (sem prefixo) — quem decide se vira `last_*` ou `first_*` é o
# `OriginRecorder`.
#
# O que esta camada NÃO tem, e por isso não finge ter: `document.referrer`. O SDK manda
# `document.location.href` (`sdk/DOMHelpers.js:52`), então o host aqui é o do PRÓPRIO site do
# cliente — daí os nomes `page_host`/`page_path`. Origem externa real é C2.
class Tracking::OriginParser
  IA_GENERATIVA_HOSTS = %w[
    chatgpt.com chat.openai.com openai.com perplexity.ai gemini.google.com bard.google.com
    claude.ai copilot.microsoft.com
  ].freeze

  # O ChatGPT carimba `utm_source=chatgpt.com` nos links que abre; a Perplexity usa
  # `utm_source=perplexity`. Sem `document.referrer`, é por aqui que a origem de IA se identifica.
  IA_GENERATIVA_TOKENS = %w[chatgpt openai perplexity gemini bard claude copilot].freeze

  SEARCH_HOSTS = %w[google bing duckduckgo yahoo ecosia yandex baidu brave].freeze
  SOCIAL_HOSTS = %w[facebook instagram linkedin twitter x.com tiktok pinterest reddit youtube threads whatsapp telegram].freeze

  PAID_SEARCH_MEDIUMS = %w[cpc ppc paidsearch paid_search paid-search sem cpm display].freeze
  SOCIAL_MEDIUMS = %w[social paid_social paidsocial paid-social social-media social_media].freeze
  EMAIL_MEDIUMS = %w[email e-mail e_mail newsletter mail].freeze
  ORGANIC_MEDIUMS = %w[organic organico orgânico].freeze

  # Só estas três são normalizadas para minúsculas: são as que o relatório do 1.22 agrupa, e
  # `Google` + `google` em colunas separadas é o relatório mentindo sobre duas campanhas.
  # Click id NUNCA é normalizado — é case-sensitive por definição.
  DOWNCASED_KEYS = %w[utm_source utm_medium utm_campaign].freeze

  def initialize(url)
    @url = url
  end

  # Devolve só o que existe. Chave ausente não vira string vazia: ausência é ausência.
  def attributes
    return {} if uri.blank?

    attrs = extracted_params
    attrs['page_host'] = page_host if page_host.present?
    attrs['page_path'] = page_path if page_path.present?
    attrs['origin_kind'] = origin_kind(attrs)
    attrs
  end

  private

  attr_reader :url

  def uri
    return @uri if defined?(@uri)

    @uri = begin
      parsed = URI.parse(url.to_s)
      parsed.is_a?(URI::HTTP) || parsed.is_a?(URI::HTTPS) ? parsed : nil
    rescue StandardError
      nil
    end
  end

  def query_params
    @query_params ||= begin
      CGI.parse(uri.query.to_s).transform_keys { |key| key.to_s.strip.downcase }
    rescue StandardError
      {}
    end
  end

  def extracted_params
    keys = Tracking::OriginAttributes::UTM_KEYS + Tracking::OriginAttributes::CLICK_ID_KEYS

    keys.each_with_object({}) do |key, acc|
      value = normalize(key, query_params[key]&.first)
      acc[key] = value if value.present?
    end
  end

  def normalize(key, value)
    value = value.to_s.strip
    return nil if value.blank?

    value = value.downcase if DOWNCASED_KEYS.include?(key)
    value[0, Tracking::OriginAttributes::MAX_VALUE_LENGTH]
  end

  def page_host
    @page_host ||= uri.host.to_s.downcase.delete_prefix('www.').presence
  end

  def page_path
    path = uri.path.to_s
    path = '/' if path.blank?
    path[0, Tracking::OriginAttributes::MAX_VALUE_LENGTH]
  end

  # Ordem é a regra. Quem paga o clique vem primeiro (o dinheiro está lá), IA generativa antes de
  # busca orgânica (senão `gemini.google.com` cai em "google"), e o fundo do poço é
  # `nao_disponivel` — NUNCA "direta". Não temos como saber que o acesso foi direto: só sabemos
  # que não recebemos dado, e as duas coisas não são a mesma.
  def origin_kind(attrs)
    source = attrs['utm_source'].to_s
    medium = attrs['utm_medium'].to_s

    return 'busca_paga' if paid_search?(attrs, medium)
    return 'email' if EMAIL_MEDIUMS.include?(medium)
    return 'ia_generativa' if ia_generativa?(source)
    return 'social' if social?(attrs, source, medium)
    return 'busca_organica' if organic_search?(source, medium)
    return 'referencia' if source.present?

    'nao_disponivel'
  end

  def paid_search?(attrs, medium)
    %w[gclid gbraid wbraid msclkid].any? { |key| attrs[key].present? } || PAID_SEARCH_MEDIUMS.include?(medium)
  end

  def ia_generativa?(source)
    return false if source.blank?

    host = source.delete_prefix('www.')
    return true if IA_GENERATIVA_HOSTS.include?(host)

    IA_GENERATIVA_TOKENS.any? { |token| host == token || host.start_with?("#{token}.") }
  end

  def social?(attrs, source, medium)
    return true if %w[fbclid ttclid].any? { |key| attrs[key].present? }
    return true if SOCIAL_MEDIUMS.include?(medium)

    SOCIAL_HOSTS.any? { |host| source == host || source.start_with?("#{host}.") }
  end

  def organic_search?(source, medium)
    return false if source.blank?
    return true if ORGANIC_MEDIUMS.include?(medium)

    SEARCH_HOSTS.any? { |host| source == host || source.start_with?("#{host}.") }
  end
end
