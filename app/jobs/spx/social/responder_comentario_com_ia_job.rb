# frozen_string_literal: true

# Chamar o modelo é lento e a Meta espera resposta rápida no webhook — por isso a IA responde
# fora do ciclo de captura. Se este job morrer, o comentário continua gravado: capturar e
# responder são independentes de propósito.
class Spx::Social::ResponderComentarioComIaJob < ApplicationJob
  queue_as :low

  def perform(comentario_id)
    comentario = Spx::Social::Comentario.find_by(id: comentario_id)
    return if comentario.blank?

    resultado = Spx::Social::ResponderComentarioComIa.new(comentario: comentario).perform
    # O motivo de não ter respondido é o que interessa no piloto — "não aconteceu nada" é a
    # pior resposta possível para quem está testando.
    Rails.logger.info("[social] IA no comentário #{comentario.external_id}: #{resumo(resultado)}")
  end

  private

  def resumo(resultado)
    return resultado.to_s unless resultado.respond_to?(:ok?)

    resultado.ok? ? "enviada (#{resultado.external_id})" : "não enviada (#{resultado.recusa || resultado.erro})"
  end
end
