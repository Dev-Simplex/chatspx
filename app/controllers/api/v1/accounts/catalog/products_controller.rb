# frozen_string_literal: true

# CRUD interno do catálogo (C2) — o que a aba Catálogo e a tela de cadastro consomem.
#
# A API do ERP (C3) é outra porta, com outra autenticação e idempotência por SKU. Aqui é o
# painel: quem fala é um usuário da conta, e o id é o da tabela.
class Api::V1::Accounts::Catalog::ProductsController < Api::V1::Accounts::BaseController
  RESULTADOS_POR_PAGINA = 25

  before_action :produto, except: [:index, :create]
  before_action :check_authorization

  # A vitrine precisa do total para paginar, então a resposta é objeto com `meta`, e não array
  # solto: sem o total, a tela não sabe se existe página seguinte.
  def index
    escopo = filtrar(policy_scope(CatalogProduct).includes(:category, images_attachments: :blob))
    @total = escopo.count
    @pagina = params[:page].presence&.to_i || 1
    @produtos = escopo.order(featured: :desc, name: :asc).page(@pagina).per(RESULTADOS_POR_PAGINA)
  end

  def show; end

  def create
    @produto = Current.account.catalog_products.create!(produto_params)
    anexar_imagens
    render :show, status: :created
  end

  def update
    @produto.update!(produto_params)
    anexar_imagens
    render :show
  end

  def destroy
    @produto.destroy!
    head :ok
  end

  # Apagar UMA foto sem mexer no resto: `images` é lista, e mandar a lista nova no update
  # ACRESCENTA em vez de substituir (ver `anexar_imagens`).
  def destroy_image
    imagem = @produto.images.find(params[:image_id])
    imagem.purge_later
    render :show
  end

  private

  def produto
    @produto ||= policy_scope(CatalogProduct).find(params[:id])
  end

  def check_authorization
    authorize(@produto || CatalogProduct)
  end

  # Busca por nome OU SKU é o que o atendente faz no meio do atendimento: ele tem o código do
  # produto na mão ou o nome na cabeça, nunca os dois.
  def filtrar(escopo)
    escopo = escopo.where('catalog_products.name ILIKE :t OR catalog_products.sku ILIKE :t', t: "%#{params[:q]}%") if params[:q].present?
    escopo = escopo.da_categoria(params[:category_id]) if params[:category_id].present?
    escopo = escopo.visiveis if ActiveModel::Type::Boolean.new.cast(params[:visible_only])
    escopo
  end

  # Anexa SEM apagar o que já existe: quem tira foto usa `destroy_image`. Substituir aqui faria a
  # tela perder as fotos antigas a cada salvar que mandasse uma nova.
  def anexar_imagens
    imagens = params.dig(:catalog_product, :images)
    @produto.images.attach(imagens) if imagens.present?
  end

  def produto_params
    params.require(:catalog_product).permit(
      :name, :description, :price_cents, :promo_price_cents, :currency,
      :sku, :stock, :visible, :featured, :catalog_category_id
    )
  end
end
