# frozen_string_literal: true

# Envio de resposta a um comentário do Instagram, nas duas formas que a plataforma tem.
#
# Elas NÃO são variação de estilo — são superfícies diferentes:
#
#   pública  POST /{comment_id}/replies            aparece embaixo do post, para qualquer pessoa
#   privada  POST /{ig_id}/messages                cai no direct do autor, só ele lê
#            com recipient: {comment_id: ...}
#
# ⚠️ A PRIVADA É UMA POR COMENTÁRIO, e tem janela a partir do comentário. Não há segunda
# chance: por isso quem chama registra a tentativa antes de qualquer retry.
#
# OBSERVADO, não só documentado (26/08): a primeira resposta privada a um comentário devolveu
# 200 com `message_id`; a segunda, ao MESMO comentário, devolveu `HTTP 500 code=1 — An unknown
# error has occurred`. A Meta não diz "já respondido"; ela devolve erro genérico. Quem tratar
# esse 500 como falha transitória e tentar de novo vai insistir para sempre num pedido que
# nunca vai passar — a guarda de idempotência é o que impede isso.
#
# Estado medido em 25/08 com o token da inbox 57 (sondagem contra id inexistente, nada
# publicado): a privada devolveu `400 / 2534014 — usuário não encontrado`, que é erro de OBJETO
# e prova que forma e escopo passam. A pública devolveu `500 code=1` genérico, que não distingue
# permissão de parâmetro — **a capacidade dela segue desconhecida até o primeiro envio real.**
class Spx::Social::InstagramResposta
  pattr_initialize [:comentario!, :texto!, :forma!]

  Resultado = Data.define(:ok, :external_id, :erro) do
    def ok? = ok
  end

  def perform
    resposta = forma.to_s == 'publica' ? enviar_publica : enviar_privada
    interpretar(resposta)
  rescue StandardError => e
    Rails.logger.error("[social] erro ao responder comentário #{comentario.external_id}: #{e.message}")
    Resultado.new(ok: false, external_id: nil, erro: "#{e.class}: #{e.message}")
  end

  private

  def enviar_publica
    HTTParty.post("#{base_uri}/#{comentario.external_id}/replies",
                  body: { message: texto, access_token: token })
  end

  def enviar_privada
    HTTParty.post("#{base_uri}/#{canal.instagram_id}/messages",
                  body: {
                    recipient: { comment_id: comentario.external_id }.to_json,
                    message: { text: texto }.to_json,
                    access_token: token
                  })
  end

  # A Meta responde 200 com `error` no corpo em alguns caminhos, então status sozinho não basta —
  # é o mesmo defeito que fazia o `subscribe` tratar recusa como sucesso.
  def interpretar(resposta)
    corpo = resposta.parsed_response.is_a?(Hash) ? resposta.parsed_response : {}
    erro = corpo['error']

    return sucesso(corpo) if resposta.success? && erro.blank?

    detalhe = "#{erro&.dig('code')}/#{erro&.dig('error_subcode')} #{erro&.dig('message')}".strip
    Rails.logger.error(
      "[social] resposta #{forma} recusada no comentário #{comentario.external_id}: " \
      "HTTP #{resposta.code} #{detalhe}"
    )
    Resultado.new(ok: false, external_id: nil, erro: detalhe.presence || "HTTP #{resposta.code}")
  end

  # A pública devolve `id` (o do comentário criado); a privada devolve `message_id`.
  def sucesso(corpo)
    Resultado.new(ok: true, external_id: corpo['id'] || corpo['message_id'], erro: nil)
  end

  def canal
    @canal ||= comentario.inbox.channel
  end

  def token
    canal.access_token
  end

  def base_uri
    "https://graph.instagram.com/#{GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0')}"
  end
end
