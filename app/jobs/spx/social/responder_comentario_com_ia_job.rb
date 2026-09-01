# frozen_string_literal: true

# Chamar o modelo é lento e a Meta espera resposta rápida no webhook — por isso a IA responde
# fora do ciclo de captura. Se este job morrer, o comentário continua gravado: capturar e
# responder são independentes de propósito.
class Spx::Social::ResponderComentarioComIaJob < ApplicationJob
  queue_as :low

  def perform(comentario_id)
    comentario = Spx::Social::Comentario.find_by(id: comentario_id)
    return if comentario.blank?

    # A leitura das imagens vem ANTES da resposta, e no mesmo job de propósito: sem ela a IA
    # responde "consulte no direct" a uma pergunta cujo preço está na frente de quem perguntou
    # (medido em 26/08). Ler é lento; por isso este job vive na fila `low`.
    ler_midia(comentario.publicacao)

    resultado = Spx::Social::ResponderComentarioComIa.new(comentario: comentario.reload).perform
    # O motivo de não ter respondido é o que interessa no piloto — "não aconteceu nada" é a
    # pior resposta possível para quem está testando.
    Rails.logger.info("[social] IA no comentário #{comentario.external_id}: #{resumo(resultado)}")
  end

  private

  # Best-effort: publicação sem leitura ainda responde, só com menos contexto. Falha aqui não
  # pode calar a IA — seria trocar uma resposta pobre por resposta nenhuma.
  def ler_midia(publicacao)
    return if publicacao.blank?

    resultado = Spx::Social::LerMidiaDaPublicacao.new(publicacao: publicacao).perform
    Rails.logger.info("[social] leitura da publicacao #{publicacao.external_id}: #{resultado}")
  rescue StandardError => e
    Rails.logger.error("[social] leitura falhou: #{e.class} #{e.message}")
  end

  def resumo(resultado)
    return resultado.to_s unless resultado.respond_to?(:ok?)

    resultado.ok? ? "enviada (#{resultado.external_id})" : "não enviada (#{resultado.recusa || resultado.erro})"
  end
end
