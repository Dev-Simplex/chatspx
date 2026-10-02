# frozen_string_literal: true

# CRUD interno do catálogo (C2) — o que a aba Catálogo e a tela de cadastro consomem.
#
# A API do ERP (C3) é outra porta, com outra autenticação e idempotência por SKU. Aqui é o
# painel: quem fala é um usuário da conta, e o id é o da tabela.
class Api::V1::Accounts::Catalog::ProductsController < Api::V1::Accounts::BaseController
  RESULTADOS_POR_PAGINA = 25

  before_action :produto, except: [:index, :create, :import, :import_status, :sync]
  before_action :check_authorization
  before_action :exigir_espelho, only: [:sync, :sync_product]

  helper_method :meta_sync_enabled?, :campos_personalizados

  rescue_from CustomExceptions::Catalog::InvalidCustomField, with: :render_error_response

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

  # Import por planilha (C5). Assíncrono: a planilha do cliente pode ter milhares de linhas, e
  # segurar a requisição até o fim entregaria timeout em vez de resultado.
  def import
    return render json: { error: I18n.t('errors.contacts.import.failed') }, status: :unprocessable_entity if params[:import_file].blank?

    importacao = nil
    ActiveRecord::Base.transaction do
      importacao = Current.account.data_imports.create!(data_type: 'catalog_products')
      importacao.import_file.attach(params[:import_file])
    end
    render json: resumo_da_importacao(importacao), status: :accepted
  end

  # Andamento e relatório de erro por linha. Sem tela ainda (a C6/C7 são do canal), é por aqui que
  # o cliente busca o CSV das linhas recusadas.
  def import_status
    importacao = Current.account.data_imports.find(params[:import_id])
    render json: resumo_da_importacao(importacao)
  end

  # Apagar UMA foto sem mexer no resto: `images` é lista, e mandar a lista nova no update
  # ACRESCENTA em vez de substituir (ver `anexar_imagens`).
  def destroy_image
    imagem = @produto.images.find(params[:image_id])
    imagem.purge_later
    render :show
  end

  # Espelho da Meta (F3). O job é POR CONTA: sincronizar tudo e sincronizar um produto enfileiram a
  # mesma passada. Assíncrono, então a resposta não diz "sincronizado" — o produto segue pendente
  # até o job carimbá-lo.
  def sync
    Catalog::MetaSyncJob.perform_later(Current.account)
    render json: { queued: true }, status: :accepted
  end

  def sync_product
    @produto.pedir_sincronizacao!
    Catalog::MetaSyncJob.perform_later(Current.account)
    render :show, status: :accepted
  end

  private

  # Mesma checagem do serviço: conta sem catálogo ou sem caixa `whatsapp_cloud` não tem espelho.
  def meta_sync_enabled?
    return @meta_sync_enabled if defined?(@meta_sync_enabled)

    @meta_sync_enabled = Catalog::MetaSyncService.new(Current.account).configurado?
  end

  # Sem isto o botão enfileiraria um job que termina em silêncio, e o usuário acharia que funcionou.
  def exigir_espelho
    render json: { error: I18n.t('catalog.meta_sync.not_configured') }, status: :unprocessable_entity unless meta_sync_enabled?
  end

  def produto
    @produto ||= policy_scope(CatalogProduct).find(params[:id])
  end

  def resumo_da_importacao(importacao)
    {
      id: importacao.id,
      status: importacao.status,
      processed_records: importacao.processed_records,
      total_records: importacao.total_records,
      failed_records: importacao.total_records.to_i - importacao.processed_records.to_i,
      failed_records_url: importacao.failed_records.attached? ? url_for(importacao.failed_records) : nil
    }
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

  def campos_personalizados
    @campos_personalizados ||= Catalog::CustomFields.new(Current.account)
  end

  # A tela manda TODAS as chaves dos campos personalizados, então o conjunto é substituído: chave
  # que veio em branco some. Sem a chave `custom_attributes` no corpo, os campos ficam como estão.
  def produto_params
    atributos = params.require(:catalog_product).permit(
      :name, :description, :price_cents, :promo_price_cents, :currency,
      :sku, :stock, :visible, :featured, :catalog_category_id, custom_attributes: {}
    )
    return atributos unless atributos.key?(:custom_attributes)

    atuais = @produto&.custom_attributes || {}
    atributos.merge(custom_attributes: campos_personalizados.normalizar(atributos[:custom_attributes], atuais))
  end
end
