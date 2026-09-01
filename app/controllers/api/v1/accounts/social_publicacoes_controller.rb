# frozen_string_literal: true

# Página Rede Social, aba Publicações — Fase 1 da `docs/SPEC-instagram-social.md`.
#
# O cache que esta aba mostra é o MESMO dado que a IA precisa para responder um comentário: sem
# legenda e miniatura ela responderia "quanto custa?" sem saber do quê. Tela e cérebro são a
# mesma obra — é o argumento da SPEC para fazer as duas juntas.
class Api::V1::Accounts::SocialPublicacoesController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  def index
    @publicacoes = Spx::Social::Publicacao
                   .where(account_id: Current.account.id)
                   .order(Arel.sql('publicada_em DESC NULLS LAST'), id: :desc)
                   .limit(100)
    # Quantos comentários capturamos por publicação. NÃO é o total do Instagram — esse vem em
    # `metricas['comments_count']`, e a diferença entre os dois é justamente o que a assinatura
    # não trouxe (comentário anterior a 18/08, ou publicação em colab, que a Meta não entrega).
    @capturados = Spx::Social::Comentario
                  .where(account_id: Current.account.id, publicacao_id: @publicacoes.map(&:id))
                  .group(:publicacao_id, :proprio)
                  .count
  end
end
