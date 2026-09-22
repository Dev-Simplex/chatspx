# CRUD de message templates (HSM) de um canal WhatsApp Cloud API.
# Cria/lista/remove templates direto da Graph API da Meta — sem precisar abrir
# o WhatsApp Manager. Status de aprovação volta como PENDING; sincroniza via
# Channel::Whatsapp#sync_templates.
class Api::V1::Accounts::InboxMessageTemplatesController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  before_action :validate_cloud_channel

  def index
    result = service.list
    if result[:success]
      render json: { templates: result[:templates], media_upload_enabled: upload_service.configured? }
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  # Sobe a mídia do cabeçalho e devolve o handle da Meta. É passo separado da
  # criação porque o `example.header_handle` do template exige um handle que só
  # existe depois do upload — URL o endpoint de templates não aceita.
  def upload_media
    file = params[:file]
    # Texto solto no lugar do arquivo passa pelo `blank?` e estoura no
    # original_filename: a fronteira exige um upload de verdade.
    return render json: { error: 'File is required' }, status: :unprocessable_entity unless file.respond_to?(:original_filename)

    result = upload_service.upload(file, file_name: file.original_filename, file_type: file.content_type)

    if result[:success]
      render json: { handle: result[:handle] }
    else
      render json: { error: result[:error], details: result[:response_body] }, status: :unprocessable_entity
    end
  rescue Whatsapp::ResumableUploadService::MissingAppIdError, Whatsapp::ResumableUploadService::UnsupportedFileTypeError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def create
    result = service.create(
      name: template_params[:name],
      language: template_params[:language] || 'pt_BR',
      category: template_params[:category] || 'UTILITY',
      components: template_params[:components]
    )

    if result[:success]
      render json: { template: result.slice(:template_id, :template_name, :category, :language, :status) }, status: :created
    else
      render json: { error: result[:error], details: result[:response_body] }, status: :unprocessable_entity
    end
  rescue Whatsapp::TemplateManagementService::InvalidCategoryError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActionController::ParameterMissing
    render json: { error: 'Template parameters are required' }, status: :unprocessable_entity
  end

  def destroy
    result = service.delete(params[:id])
    if result[:success]
      head :ok
    else
      render json: { error: 'Delete failed', details: result[:response_body] }, status: :unprocessable_entity
    end
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :show?
  end

  def validate_cloud_channel
    return if @inbox.channel_type == 'Channel::Whatsapp' && @inbox.channel.provider_config['business_account_id'].present?

    render json: { error: 'Message templates só estão disponíveis para inboxes WhatsApp Cloud API (com business_account_id)' },
           status: :bad_request
  end

  def service
    @service ||= Whatsapp::TemplateManagementService.new(@inbox.channel)
  end

  def upload_service
    @upload_service ||= Whatsapp::ResumableUploadService.new(@inbox.channel)
  end

  # components é um array aninhado livre no formato Graph API
  # (HEADER/BODY/FOOTER/BUTTONS). Strong params não modela bem estrutura
  # arbitrária aninhada, então pega name/language/category via permit e
  # components via to_unsafe_h do bloco template.
  def template_params
    permitted = params.require(:template).permit(:name, :language, :category)
    raw = params.require(:template).to_unsafe_h
    permitted[:components] = raw[:components]
    permitted
  end
end
