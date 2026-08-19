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
class TrackingDelivery < ApplicationRecord
  belongs_to :tracking_event

  # Os tres primeiros sao client-side (a ponte de tags, 5.10); os tres ultimos, server-side (5.11).
  enum destination: { data_layer: 0, meta_pixel: 1, ga4_gtag: 2, meta_capi: 3, ga4_mp: 4, google_ads: 5 }
  # `dead` e a DLQ: acabaram as tentativas e o evento NAO some — fica visivel no painel de 5.14.
  enum status: { pending: 0, sent: 1, failed: 2, skipped: 3, dead: 4 }

  before_validation :ensure_field_names

  validate :ensure_field_names_are_names

  private

  def ensure_field_names
    self.field_names = [] if field_names.blank?
  end

  def ensure_field_names_are_names
    return if field_names.is_a?(Array) && field_names.all?(String)

    errors.add(:field_names, 'deve ser uma lista de nomes de campo, nunca valores')
  end
end
