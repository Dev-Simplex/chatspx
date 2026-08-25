# frozen_string_literal: true

# Página Rede Social, aba Comentários — Fase 1 da `docs/SPEC-instagram-social.md`.
#
# É aqui que mora a auditoria que a decisão "comentário não vira conversa" tirou: sem esta tela,
# o comentário é capturado e ninguém o vê. Ela responde a pergunta original do cliente — "onde
# está?" — e a do operador — "o que falta responder?".
#
# Admin-only, como a SPEC pede na §5.
class Api::V1::Accounts::SocialComentariosController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  RESULTADOS_POR_PAGINA = 50

  def index
    @comentarios = pagina
    # A inferência de "respondido" precisa das respostas da conta, que o filtro padrão esconde.
    # Por isso ela é calculada sobre as publicações EM TELA, e não sobre a página filtrada.
    @respondidos = Spx::Social::Respondidos.new(comentarios_das_publicacoes_em_tela)
  end

  private

  def pagina
    escopo = base
    escopo = escopo.de_terceiros unless incluir_proprios?
    escopo = escopo.where(publicacao_id: params[:publicacao_id]) if params[:publicacao_id].present?
    escopo.includes(:publicacao)
          .order(comentado_em: :desc, id: :desc)
          .limit(RESULTADOS_POR_PAGINA)
          .offset(offset)
  end

  def comentarios_das_publicacoes_em_tela
    ids = @comentarios.filter_map(&:publicacao_external_id).uniq
    return [] if ids.empty?

    base.da_conta.where(publicacao_external_id: ids)
  end

  def incluir_proprios?
    ActiveModel::Type::Boolean.new.cast(params[:incluir_proprios]).present?
  end

  def offset
    [params[:pagina].to_i - 1, 0].max * RESULTADOS_POR_PAGINA
  end

  def base
    Spx::Social::Comentario.where(account_id: Current.account.id)
  end
end
