# frozen_string_literal: true

# A Meta como ela CONTA (bloco 5.13). Nao e um spec: entra por `require_relative`.
#
# Regra publicada: dedup por (`event_id`, `event_name`) dentro de 48 h; passada a janela, o mesmo par
# entra como evento novo. E o unico jeito de o spec falar do NUMERO que o cliente ve, e nao do
# payload que o servidor mandou — que e onde a conversao dobrada se esconde.
class MetaCounter
  attr_reader :counted

  def initialize
    @first_seen = {}
    @counted = 0
  end

  def receive(event_id:, event_name:, at:)
    key = [event_id, event_name]
    first = @first_seen[key]
    return if first && (at - first) <= Tracking::DedupWindow::WINDOW

    @first_seen[key] = at
    @counted += 1
  end
end
