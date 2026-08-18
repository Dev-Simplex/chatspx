class Captain::Llm::PdfProcessingService < Llm::LegacyBaseOpenAiService
  include Integrations::LlmInstrumentation

  # `Llm::LegacyBaseOpenAiService#initialize` nao aceita argumento. O `super(account:)`
  # daqui ficou orfao no merge do upgrade v4.12.1 (cb0d3d999f, 31/03/2026), que trouxe a
  # versao upstream do base e deixou as duas subclasses do Captain chamando o contrato
  # antigo — desde entao toda instanciacao desta classe estourava ArgumentError.
  #
  # `@account` e atribuido ANTES do `super()`: o base resolve a chave na propria
  # construcao, entao quem precisar decidir por conta ja tem o valor. Mesmo padrao do
  # Messages::AudioTranscriptionService.
  #
  # A chave continua sendo a CAPTAIN_OPEN_AI_API_KEY, e isto e deliberado, nao herdado por
  # acidente: a separacao de chaves por proposito (b1c3c7812b) escolheu eval e transcricao
  # de audio; ingestao de PDF nao entrou. Sem `api_key_config_name` sobrescrito,
  # `resolve_access_token` devolve exatamente a mesma chave de antes daquele commit.
  def initialize(document)
    @document = document
    @account = document.account
    super()
  end

  def process
    return if document.openai_file_id.present?

    file_id = upload_pdf_to_openai
    raise CustomExceptions::Pdf::UploadError, I18n.t('captain.documents.pdf_upload_failed') if file_id.blank?

    document.store_openai_file_id(file_id)
  end

  private

  attr_reader :document

  def upload_pdf_to_openai
    with_tempfile do |temp_file|
      instrument_file_upload do
        response = @client.files.upload(
          parameters: {
            file: temp_file,
            purpose: 'assistants'
          }
        )
        response['id']
      end
    end
  end

  def instrument_file_upload(&)
    return yield unless ChatwootApp.otel_enabled?

    tracer.in_span('llm.file.upload') do |span|
      span.set_attribute('gen_ai.provider', 'openai')
      span.set_attribute('file.purpose', 'assistants')
      span.set_attribute(ATTR_LANGFUSE_USER_ID, document.account_id.to_s)
      span.set_attribute(ATTR_LANGFUSE_TAGS, ['pdf_upload'].to_json)
      span.set_attribute(format(ATTR_LANGFUSE_METADATA, 'document_id'), document.id.to_s)
      file_id = yield
      span.set_attribute('file.id', file_id) if file_id
      file_id
    end
  end

  def with_tempfile
    Tempfile.create(['pdf_upload', '.pdf'], binmode: true) do |temp_file|
      document.pdf_file.blob.open do |blob_file|
        IO.copy_stream(blob_file, temp_file)
      end

      temp_file.flush
      temp_file.rewind

      yield temp_file
    end
  end
end
