# Sobe um arquivo para a Resumable Upload API da Meta e devolve o handle que o
# `example.header_handle` de um message template exige.
#
# A Meta NÃO aceita URL nesse campo: cabeçalho de mídia só é aprovado com um
# handle emitido por ela. O fluxo tem dois passos — abrir a sessão e enviar o
# binário — e roda contra o APP, não contra a WABA. Por isso o canal precisa de
# `app_id`: o `business_account_id` não serve aqui.
#
# O token do próprio canal autentica os dois passos, desde que o app pertença ao
# mesmo Business Manager da WABA.
#
# Uso:
#   svc = Whatsapp::ResumableUploadService.new(whatsapp_channel)
#   svc.upload(file, file_name: 'mapa.jpeg', file_type: 'image/jpeg')
#   # => { success: true, handle: '4:aW1hZ2Vt...' }
class Whatsapp::ResumableUploadService
  API_VERSION = 'v22.0'.freeze
  SUPPORTED_TYPES = %w[image/jpeg image/png video/mp4 video/3gpp application/pdf].freeze

  class MissingAppIdError < StandardError; end
  class UnsupportedFileTypeError < StandardError; end

  def initialize(whatsapp_channel)
    @channel = whatsapp_channel
  end

  # Sem app_id configurado não existe upload possível — a tela usa isto para
  # explicar por que o cabeçalho de mídia está indisponível, em vez de deixar o
  # usuário montar o template e tomar erro da Meta no fim.
  def configured?
    app_id.present?
  end

  def upload(file, file_name:, file_type:)
    raise MissingAppIdError, 'app_id not configured for this channel' if app_id.blank?
    raise UnsupportedFileTypeError, "file_type must be one of #{SUPPORTED_TYPES.join(', ')}" unless SUPPORTED_TYPES.include?(file_type.to_s)

    bytes = read_binary(file)
    session_id, failure = start_session(file_name, bytes.bytesize, file_type)
    return failure if session_id.blank?

    finish_upload(session_id, bytes)
  end

  private

  def read_binary(file)
    content = file.respond_to?(:read) ? file.read : file.to_s
    content.dup.force_encoding(Encoding::BINARY)
  end

  def start_session(file_name, file_length, file_type)
    response = HTTParty.post(
      "#{api_base}/#{API_VERSION}/#{app_id}/uploads",
      headers: oauth_headers,
      query: { file_name: file_name, file_length: file_length, file_type: file_type }
    )
    return [response.parsed_response['id'], nil] if response.success?

    [nil, failure(response, 'Upload session creation failed')]
  end

  def finish_upload(session_id, bytes)
    response = HTTParty.post(
      "#{api_base}/#{API_VERSION}/#{session_id}",
      headers: oauth_headers.merge('file_offset' => '0'),
      body: bytes
    )
    handle = response.parsed_response['h'] if response.success?
    return { success: true, handle: handle } if handle.present?

    failure(response, 'Media upload failed')
  end

  def failure(response, message)
    Rails.logger.error("WhatsApp resumable upload failed: #{response.code} - #{response.body}")
    { success: false, error: message, response_body: response.body }
  end

  # O segundo passo exige o esquema OAuth; Bearer é recusado pelo endpoint de
  # upload, ao contrário do resto da Graph API.
  def oauth_headers
    { 'Authorization' => "OAuth #{@channel.provider_config['api_key']}" }
  end

  # App da Meta ao qual o upload pertence. Vem da inbox porque cada cliente tem
  # o seu app — a chave global só serve a instalação dedicada a um cliente só.
  # Fica em additional_attributes, e não em provider_config, porque alterar o
  # provider_config dispara a validação de credencial contra a Meta.
  def app_id
    return @app_id if defined?(@app_id)

    @app_id = @channel.inbox&.additional_attributes&.dig('whatsapp_app_id').presence ||
              GlobalConfigService.load('WHATSAPP_APP_ID', '').presence
  end

  def api_base
    ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
  end
end
