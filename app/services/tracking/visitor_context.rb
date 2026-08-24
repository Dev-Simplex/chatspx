# frozen_string_literal: true

# Bloco 5.11 — T-C5.8 / regra RC10: IP e user-agent do VISITANTE, nunca do servidor.
#
# Esta classe existe por causa de uma tentacao especifica. Quem monta um payload de CAPI dentro de
# um job tem `request` em nenhum lugar e `Socket`/`ENV` em toda parte; a saida obvia — mandar o IP
# da maquina que rodou o job — e aceita pela Meta com 200 e DESTROI o EMQ da conta inteira, porque
# todo evento passa a vir do mesmo endereco. O erro nao tem sintoma ate o cliente comparar numeros.
#
# Entao a regra aqui e absoluta: **toda fonte e um registro do visitante**. Quando o dado nao
# existe, o campo simplesmente NAO VAI (e ha spec provando que ele nao vai), porque campo ausente
# custa um sinal e campo errado custa todos.
#
# Fontes, e por que cada uma:
#   ip                -> `contact.additional_attributes['updated_at_ip' | 'created_at_ip']`, que e
#                        onde `widgets_controller.rb:69` grava o `request.remote_ip` do visitante e
#                        de onde `contact_ip_lookup_job.rb:26` ja le.
#   user_agent        -> `conversation.additional_attributes['browser']['user_agent']`. O widget
#                        grava hoje o user-agent PARSEADO (`browser_params`), nao a string crua; a
#                        string crua e o que a CAPI quer, entao lemos a chave e aceitamos a ausencia.
#   fbc               -> derivado do `fbclid` que o bloco 1.19 gravou em `last_fbclid`, no formato
#                        `fb.1.<ms>.<fbclid>` que a Meta especifica.
#   gclid             -> `last_gclid`, mesmo caminho.
#   event_source_url  -> `last_page_host` + `last_page_path`, com o `referer` do widget de reserva.
class Tracking::VisitorContext
  IP_KEYS = %w[updated_at_ip created_at_ip].freeze

  def self.for(event)
    new(event)
  end

  def initialize(event)
    @event = event
  end

  def ip
    IP_KEYS.filter_map { |key| contact_attributes[key].presence }.first
  end

  def user_agent
    browser = conversation_attributes['browser']
    return nil unless browser.is_a?(Hash)

    browser['user_agent'].presence
  end

  # Cookie `_fbp` do navegador. So existe se a ponte de tags (5.10) o tiver devolvido ao backend;
  # ate la e `nil`, e o payload sai sem ele.
  def fbp
    conversation_attributes['fbp'].presence || contact_attributes['fbp'].presence
  end

  # A Meta nao aceita o `fbclid` cru: o campo `fbc` e `fb.<subdominio>.<ms>.<fbclid>`, e o instante
  # e o do CLIQUE. O melhor instante que temos e a criacao da conversa que carregou o clique.
  def fbc
    stored = conversation_attributes['fbc'].presence
    return stored if stored

    fbclid = origin_value('fbclid')
    return nil if fbclid.blank?

    "fb.1.#{click_timestamp_ms}.#{fbclid}"
  end

  def gclid
    origin_value('gclid')
  end

  def event_source_url
    host = origin_value('page_host')
    return referer if host.blank?

    "https://#{host}#{origin_value('page_path')}"
  end

  # Id opaco e estavel do contato. Nao e PII: dele nao se volta a nome, e-mail ou telefone — e por
  # isso ele e o unico sinal de pessoa que o modo sem PII (5.12) continua mandando.
  def external_id
    contact&.id&.to_s
  end

  # `client_id` do GA4. O formato canonico vem do cookie `_ga`; quando ele nao chegou, derivamos um
  # id DETERMINISTICO do contato — determinismo importa porque o mesmo visitante precisa cair no
  # mesmo `client_id` em toda entrega, senao cada evento vira um usuario novo no relatorio.
  def ga_client_id
    stored = conversation_attributes['ga_client_id'].presence || contact_attributes['ga_client_id'].presence
    return stored if stored
    return nil if contact.nil?

    "#{contact.id}.#{contact.created_at.to_i}"
  end

  def ga_session_id
    conversation_attributes['ga_session_id'].presence
  end

  private

  attr_reader :event

  def contact
    event.contact
  end

  def conversation
    event.conversation
  end

  def contact_attributes
    @contact_attributes ||= hash_or_empty(contact&.additional_attributes)
  end

  def conversation_attributes
    @conversation_attributes ||= hash_or_empty(conversation&.additional_attributes)
  end

  # As chaves de origem moram em `custom_attributes` (bloco 1.19), com prefixo `last_` na conversa e
  # `first_` no contato. A conversa vem primeiro: ela diz o que trouxe ESTA conversa.
  def origin_value(base_key)
    conversation_custom[Tracking::OriginAttributes.conversation_key(base_key)].presence ||
      contact_custom[Tracking::OriginAttributes.contact_key(base_key)].presence
  end

  def conversation_custom
    @conversation_custom ||= hash_or_empty(conversation&.custom_attributes)
  end

  def contact_custom
    @contact_custom ||= hash_or_empty(contact&.custom_attributes)
  end

  def referer
    conversation_attributes['referer'].presence
  end

  def click_timestamp_ms
    ((conversation&.created_at || event.occurred_at).to_f * 1000).to_i
  end

  def hash_or_empty(value)
    value.is_a?(Hash) ? value.with_indifferent_access : {}.with_indifferent_access
  end
end
