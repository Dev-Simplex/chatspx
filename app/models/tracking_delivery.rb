# frozen_string_literal: true

# == Schema Information
#
# Table name: tracking_deliveries
#
#  id                :bigint           not null, primary key
#  attempts          :integer          default(0), not null
#  delivered_at      :datetime
#  destination       :integer          not null
#  emq               :decimal(3, 1)
#  error_code        :string
#  error_message     :text
#  field_names       :jsonb            not null
#  http_status       :integer
#  last_attempted_at :datetime
#  status            :integer          default("pending"), not null
#  suppressed_field_names :jsonb       not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  tracking_event_id :bigint           not null
#
# Indexes
#
#  index_tracking_deliveries_on_event_and_destination (tracking_event_id,destination) UNIQUE
#  index_tracking_deliveries_on_status                (status)
#
# Uma linha por (evento, destino) — cada tentativa de contar o MESMO fato a um destino diferente.
# O indice unico do par e o que impede entrega dupla, e e o aceite do bloco 5.03.
#
# `field_names` guarda os NOMES dos campos enviados, nunca os valores (T-C8.1). E dele que o bloco
# 5.12 tira a prova de que o modo "sem PII" nao mandou `em`/`ph`/`fn`/`ln` — e por isso a validacao
# recusa qualquer coisa que nao seja uma lista rasa de strings: um hash aqui seria valor disfarcado.
#
# `suppressed_field_names` e o OUTRO lado da mesma frase (bloco 5.12): os nomes dos campos de pessoa
# que a base TINHA e que o modo sem PII reteve. Sem ele, "nao ha `em` em `field_names`" seria
# verdade tambem para um contato sem e-mail — a afirmacao negativa passaria no vacuo.
class TrackingDelivery < ApplicationRecord
  belongs_to :tracking_event

  # Os tres primeiros sao client-side (a ponte de tags, 5.10); os tres ultimos, server-side (5.11).
  enum destination: { data_layer: 0, meta_pixel: 1, ga4_gtag: 2, meta_capi: 3, ga4_mp: 4, google_ads: 5 }
  # `dead` e a DLQ: acabaram as tentativas e o evento NAO some — fica visivel no painel de 5.14.
  enum status: { pending: 0, sent: 1, failed: 2, skipped: 3, dead: 4 }

  # A DLQ do 5.11: o que morreu depois da ultima tentativa, mais recente primeiro. E a consulta que
  # o painel de 5.14 faz, e a razao de `dead` ser um status e nao uma linha de log.
  scope :dead_letter_queue, -> { dead.order(updated_at: :desc) }

  before_validation :ensure_field_names

  validate :ensure_field_names_are_names

  private

  def ensure_field_names
    self.field_names = [] if field_names.blank?
    self.suppressed_field_names = [] if suppressed_field_names.blank?
  end

  def ensure_field_names_are_names
    add_names_error(:field_names) unless flat_list_of_names?(field_names)
    add_names_error(:suppressed_field_names) unless flat_list_of_names?(suppressed_field_names)
  end

  def flat_list_of_names?(value)
    value.is_a?(Array) && value.all?(String)
  end

  def add_names_error(attribute)
    errors.add(attribute, 'deve ser uma lista de nomes de campo, nunca valores')
  end
end
