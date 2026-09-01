# frozen_string_literal: true

# Bloco 5.09 (T-C7.4/T-C7.6) — o consentimento vigente NO INSTANTE DO FATO, junto do fato.
#
# Coluna, e nao chave dentro de `properties`, por tres razoes que sao a diferenca entre um registro
# que serve de base legal e um que so parece servir:
#
#  1. `properties` e do CLIENTE (5.16 aceita `track()` com o que ele quiser la dentro). Consentimento
#     gravado onde o site do cliente escreve e consentimento que o site do cliente pode reescrever.
#  2. `TrackingEvent` recusa PII crua em `properties` varrendo o hash inteiro; o consentimento nao e
#     PII e nao tem por que passar por essa peneira a cada gravacao.
#  3. Auditoria de privacidade pergunta "este evento saiu com que base legal?" — e isso e uma
#     consulta por coluna, nao um `->>` dentro de um jsonb de forma livre.
#
# Default `{}` e NOT NULL: ausencia se le como "nada concedido" quando o modo de consentimento da
# inbox esta ativo, e como "o comportamento de sempre" quando esta `disabled`. Nao ha backfill —
# regra A4, ausencia tem significado.
class AddConsentToTrackingEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :tracking_events, :consent, :jsonb, default: {}, null: false
  end
end
