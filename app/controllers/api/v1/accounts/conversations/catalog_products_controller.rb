# frozen_string_literal: true

# Enviar produto do catálogo na conversa (C8).
#
# Não é o `messages_controller` com um payload especial de propósito: mandar produto é montar
# legenda, copiar foto e avisar o ERP (C4) — regra que não pode ficar espalhada em quem chama.
#
# Herdar do `Conversations::BaseController` traz de graça as três travas que já existem: acesso à
# conversa, time e isolamento por agente. O gate de atribuição vem do concern, o mesmo que a
# mensagem comum usa — senão o botão de produto viraria o furo por onde se responde conversa
# alheia com a flag ligada.
class Api::V1::Accounts::Conversations::CatalogProductsController < Api::V1::Accounts::Conversations::BaseController
  include ReplyAssignmentGateConcern

  before_action :enforce_reply_assignment_gate, only: [:create]

  def create
    # Na ordem em que o atendente marcou: é a ordem das fotos e do menu numerado na conversa.
    ids = Array(params[:product_ids]).map(&:to_i)
    produtos = policy_scope(CatalogProduct).where(id: ids).sort_by { |produto| ids.index(produto.id) }
    return render json: { error: I18n.t('catalog.send.empty') }, status: :unprocessable_entity if produtos.empty?

    mensagem = Catalog::SendProductService.new(conversation: @conversation, produtos: produtos, usuario: Current.user).perform
    render json: { id: mensagem.id, content: mensagem.content, conversation_id: @conversation.display_id,
                   products: produtos.map { |p| { id: p.id, sku: p.sku } } },
           status: :created
  end
end
