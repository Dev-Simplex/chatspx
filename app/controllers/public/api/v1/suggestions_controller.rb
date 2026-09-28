# SUG-02: recebe a sugestao do formulario publico. So cria -- nao existe leitura publica.
# Anti-spam: honeypot `website` (bot preenche, pessoa nao ve) + throttle por IP no rack-attack.
class Public::Api::V1::SuggestionsController < PublicController
  # Teto do corpo inteiro (anexo + campos): recusa cedo, antes de o arquivo virar blob.
  MAX_BODY = (Suggestion::MAX_MEDIA_SIZE_MB + 1).megabytes

  def create
    return head :ok if params[:website].present?
    return head :payload_too_large if request.content_length.to_i > MAX_BODY

    suggestion = Suggestion.new(params.permit(:name, :company, :content, :media).merge(source: :public_link))
    return render json: { error: suggestion.errors.full_messages.to_sentence }, status: :unprocessable_entity unless suggestion.save

    head :created
  end
end
