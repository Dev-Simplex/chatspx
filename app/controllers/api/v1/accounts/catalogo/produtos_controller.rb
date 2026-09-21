# frozen_string_literal: true

# API pública do catálogo para o ERP do cliente (C3).
#
# Diferenças para o CRUD do painel (C2), e elas são o motivo de existirem duas portas:
#
# - a **chave é o SKU**, não o id da nossa tabela. O ERP não conhece o nosso id, e não deveria.
# - **idempotente**: mandar o mesmo SKU duas vezes atualiza, nunca duplica. É o que permite ao
#   cliente reprocessar a fila dele sem medo.
# - **apagar é desativar**: produto que some do ERP vira invisível, e não sumido. Assim o histórico
#   de envio na conversa continua reconstruível.
# - autentica com token de usuário-robô (agente), que o cliente cria para o ERP.
class Api::V1::Accounts::Catalogo::ProdutosController < Api::V1::Accounts::BaseController
  POR_PAGINA_PADRAO = 50
  POR_PAGINA_MAXIMO = 200
  LOTE_MAXIMO = 500

  before_action :check_authorization
  before_action :validar_data_do_filtro, only: [:index]

  def index
    escopo = filtrar(policy_scope(CatalogProduct).includes(:category, images_attachments: :blob))
    @total = escopo.count
    @pagina = params[:page].presence&.to_i || 1
    @por_pagina = [params[:por_pagina].presence&.to_i || POR_PAGINA_PADRAO, POR_PAGINA_MAXIMO].min
    @produtos = escopo.order(:sku, :id).page(@pagina).per(@por_pagina)
  end

  # Cria OU atualiza pelo SKU. Sem SKU não há idempotência, então sem SKU não há contrato.
  def create
    @produto = gravar_por_sku(produto_params)
    render :show, status: @criado ? :created : :ok
  end

  # PUT /produtos/:sku — o ERP manda o que mudou (tipicamente preço e estoque).
  def update
    @produto = por_sku!(params[:sku])
    @produto.update!(produto_params.except(:sku))
    render :show
  end

  # DELETE /produtos/:sku — DESATIVA. Apagar levaria junto o histórico do que já foi enviado.
  def destroy
    @produto = por_sku!(params[:sku])
    @produto.update!(visible: false)
    render :show
  end

  # Lote: o ERP manda até 500 por chamada e recebe o resultado LINHA A LINHA. Sem transação de
  # propósito — uma linha ruim não pode derrubar as outras 499, e o cliente precisa saber qual foi.
  def lote
    itens = params.require(:produtos)
    return render json: { error: "Máximo de #{LOTE_MAXIMO} produtos por chamada" }, status: :unprocessable_entity if itens.size > LOTE_MAXIMO

    @resultados = itens.map { |item| gravar_item_do_lote(item) }
    @resumo = @resultados.group_by { |r| r[:status] }.transform_values(&:size)
    render :lote
  end

  private

  def check_authorization
    authorize(CatalogProduct, :sincronizar_erp?)
  end

  def filtrar(escopo)
    escopo = escopo.where('catalog_products.name ILIKE :t OR catalog_products.sku ILIKE :t', t: "%#{params[:q]}%") if params[:q].present?
    # O ERP que sincroniza em ciclo só quer o que mudou desde a última vez.
    escopo = escopo.where(updated_at: @desde..) if @desde
    escopo
  end

  # Data malformada levantava ArgumentError e virava 500 — o cliente ficava sem saber o que errou.
  # Pior: `Time.zone.parse` devolve nil em vez de erro para outros lixos, e aí o filtro sumia em
  # silêncio e o ERP achava que tinha recebido o recorte que pediu.
  def validar_data_do_filtro
    return if params[:atualizados_apos].blank?

    @desde = begin
      Time.zone.parse(params[:atualizados_apos])
    rescue ArgumentError
      nil
    end
    return if @desde

    render json: { error: 'atualizados_apos deve ser uma data ISO 8601, por exemplo 2026-09-21T10:00:00Z' },
           status: :unprocessable_entity
  end

  def por_sku!(sku)
    policy_scope(CatalogProduct).find_by!(sku: sku.to_s.strip)
  end

  # `@criado` diz ao chamador se nasceu agora (201) ou foi atualizado (200).
  def gravar_por_sku(atributos)
    sku = atributos[:sku].to_s.strip
    raise ActionController::ParameterMissing, :sku if sku.blank?

    produto = policy_scope(CatalogProduct).find_by(sku: sku)
    @criado = produto.nil?
    produto ||= Current.account.catalog_products.new
    produto.update!(atributos.merge(sku: sku))
    produto
  end

  def gravar_item_do_lote(item)
    atributos = normalizar(item.permit(*CAMPOS_PERMITIDOS))
    produto = gravar_por_sku(atributos)
    { sku: produto.sku, status: @criado ? 'criado' : 'atualizado', id: produto.id }
  rescue ActiveRecord::RecordInvalid => e
    { sku: item[:sku], status: 'erro', erros: e.record.errors.full_messages }
  rescue ActionController::ParameterMissing
    { sku: nil, status: 'erro', erros: ['SKU é obrigatório'] }
  end

  CAMPOS_PERMITIDOS = [:name, :description, :price_cents, :promo_price_cents, :currency,
                       :sku, :stock, :visible, :featured, :categoria].freeze

  def produto_params
    normalizar(params.require(:produto).permit(*CAMPOS_PERMITIDOS))
  end

  # O ERP fala por NOME de categoria — ele não conhece o nosso id. Categoria que ainda não existe
  # é criada na hora: obrigar o cliente a cadastrar categoria por outra porta antes de mandar
  # produto transformaria uma integração em duas.
  def normalizar(atributos)
    nome = atributos.delete(:categoria)
    return atributos if nome.blank?

    categoria = Current.account.catalog_categories.find_or_create_by!(name: nome.to_s.strip)
    atributos.merge(catalog_category_id: categoria.id)
  end
end
