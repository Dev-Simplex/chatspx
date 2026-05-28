# Gerencia message templates (HSM) de um canal WhatsApp Cloud API via Graph API.
# Generalização do Whatsapp::CsatTemplateService — aceita qualquer categoria e
# componentes (HEADER/BODY/FOOTER/BUTTONS) no formato da Graph API.
#
# Requer inbox Cloud API (provider_config com business_account_id + api_key).
# Não funciona com WAHA (Channel::Api).
#
# Uso:
#   svc = Whatsapp::TemplateManagementService.new(whatsapp_channel)
#   svc.create(
#     name: 'tozi_lead_inicial',
#     language: 'pt_BR',
#     category: 'MARKETING',
#     components: [{ type: 'BODY', text: 'Oi {{1}}! ...', example: { body_text: [['Maria']] } }]
#   )
#   svc.list
#   svc.status('tozi_lead_inicial')
#   svc.delete('tozi_lead_inicial')
class Whatsapp::TemplateManagementService
  API_VERSION = 'v22.0'.freeze
  PENDING = 'PENDING'.freeze
  VALID_CATEGORIES = %w[MARKETING UTILITY AUTHENTICATION].freeze

  class InvalidCategoryError < StandardError; end

  def initialize(whatsapp_channel)
    @channel = whatsapp_channel
  end

  def create(name:, language:, category:, components:)
    normalized_category = category.to_s.upcase
    raise InvalidCategoryError, "category must be one of #{VALID_CATEGORIES.join(', ')}" unless VALID_CATEGORIES.include?(normalized_category)

    body = {
      name: normalize_name(name),
      language: language,
      category: normalized_category,
      components: components
    }

    response = HTTParty.post("#{waba_path}/message_templates", headers: api_headers, body: body.to_json)
    build_create_result(response, body)
  end

  def list
    response = HTTParty.get("#{waba_path}/message_templates?limit=100&fields=name,status,category,language,components,id", headers: api_headers)
    return { success: false, error: response.body } unless response.success?

    { success: true, templates: Array(response.parsed_response['data']) }
  end

  def status(name)
    response = HTTParty.get("#{waba_path}/message_templates?name=#{name}", headers: api_headers)
    if response.success? && response['data']&.any?
      t = response['data'].first
      { success: true, template: t.slice('id', 'name', 'status', 'category', 'language') }
    else
      { success: false, error: 'Template not found' }
    end
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def delete(name)
    response = HTTParty.delete("#{waba_path}/message_templates?name=#{name}", headers: api_headers)
    { success: response.success?, response_body: response.body }
  end

  private

  # Meta exige: lowercase, alfanumérico + underscore, sem espaços.
  def normalize_name(name)
    name.to_s.strip.downcase.gsub(/[^a-z0-9_]/, '_').squeeze('_')
  end

  def build_create_result(response, body)
    if response.success?
      {
        success: true,
        template_id: response['id'],
        template_name: body[:name],
        category: body[:category],
        language: body[:language],
        status: response['status'] || PENDING
      }
    else
      Rails.logger.error("WhatsApp template creation failed: #{response.code} - #{response.body}")
      { success: false, error: 'Template creation failed', response_body: response.body }
    end
  end

  def waba_path
    "#{api_base}/#{API_VERSION}/#{@channel.provider_config['business_account_id']}"
  end

  def api_headers
    {
      'Authorization' => "Bearer #{@channel.provider_config['api_key']}",
      'Content-Type' => 'application/json'
    }
  end

  def api_base
    ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
  end
end
