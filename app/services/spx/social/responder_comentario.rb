# frozen_string_literal: true

# Portão + envio + registro, nesta ordem. É o único caminho por onde uma resposta a comentário
# sai do SPX — a tela chama isto, e qualquer automação futura também deve chamar.
#
# A ordem importa: o portão decide ANTES de falar com a Meta, porque a resposta privada é uma
# por comentário e não há como desfazer um envio.
class Spx::Social::ResponderComentario
  pattr_initialize [:comentario!, :texto!, :forma!]

  Resultado = Data.define(:ok, :recusa, :external_id, :erro) do
    def ok? = ok
  end

  def perform
    return recusado(:texto_vazio) if texto.to_s.strip.blank?

    recusa = politica.motivo_da_recusa(comentario, forma)
    return recusado(recusa) if recusa

    envio = enviar_e_registrar
    Resultado.new(ok: envio.ok?, recusa: nil, external_id: envio.external_id, erro: envio.erro)
  end

  private

  def enviar_e_registrar
    envio = Spx::Social::InstagramResposta.new(
      comentario: comentario, texto: texto.to_s.strip, forma: forma
    ).perform
    # Registra SEMPRE, inclusive a falha. Tentativa que some do registro vira retry cego, e um
    # retry cego numa resposta privada queima a única chance que existe.
    comentario.registrar_resposta!(forma, external_id: envio.external_id, erro: envio.erro)
    envio
  end

  def recusado(motivo)
    Resultado.new(ok: false, recusa: motivo, external_id: nil, erro: nil)
  end

  def politica
    @politica ||= Spx::Social::PoliticaDeResposta.new(account: comentario.account)
  end
end
