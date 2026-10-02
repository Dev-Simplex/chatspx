# frozen_string_literal: true

# Categorias do catálogo (C2). São poucas e sempre editadas como lista, então não há paginação:
# a tela carrega todas para montar o filtro da vitrine.
class Api::V1::Accounts::Catalog::CategoriesController < Api::V1::Accounts::BaseController
  before_action :categoria, except: [:index, :create]
  before_action :check_authorization

  def index
    @categorias = policy_scope(CatalogCategory).left_joins(:products)
                                               .select('catalog_categories.*, COUNT(catalog_products.id) AS produtos_count')
                                               .group('catalog_categories.id').order(:name)
  end

  def create
    @categoria = Current.account.catalog_categories.create!(categoria_params)
    render :show, status: :created
  end

  def update
    @categoria.update!(categoria_params)
    render :show
  end

  # Apagar categoria NÃO apaga produto: ele volta para "sem categoria" (a FK faz nullify).
  def destroy
    @categoria.destroy!
    head :ok
  end

  private

  def categoria
    @categoria ||= policy_scope(CatalogCategory).find(params[:id])
  end

  def check_authorization
    authorize(@categoria || CatalogCategory)
  end

  def categoria_params
    params.require(:catalog_category).permit(:name)
  end
end
