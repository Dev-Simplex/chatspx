# Contextual Retrieval (Anthropic): antes de embeddar um chunk, um LLM gera 1-2 frases
# situando o trecho no documento. Reduz muito a falha de recuperação em docs estruturados.
# Opcional (controlado por config) por adicionar 1 chamada LLM barata por chunk.
class Captain::Llm::ContextualChunkService < Llm::BaseAiService
  include Integrations::LlmInstrumentation

  MAX_DOC_CHARS = 8000

  def initialize(document_content, account_id: nil)
    super(account: Account.find_by(id: account_id))
    @document_content = document_content.to_s[0, MAX_DOC_CHARS]
    @account_id = account_id
  end

  # Retorna "contexto + chunk" pronto pra embedding; em falha, devolve o chunk puro.
  def contextualize(chunk)
    return chunk if @document_content.blank? || chunk.blank?

    context = instrument_llm_call(instrumentation_params(chunk)) do
      chat(temperature: 0)
        .with_instructions(system_prompt)
        .ask(user_prompt(chunk))
    end.content.to_s.strip

    context.present? ? "#{context}\n\n#{chunk}" : chunk
  rescue RubyLLM::Error => e
    Rails.logger.warn("[ContextualChunk] falha (#{e.message}); usando chunk sem contexto")
    chunk
  end

  def feature_name
    'contextual_chunk'
  end

  private

  def system_prompt
    'Você situa um trecho dentro de um documento maior para melhorar a busca. ' \
      'Responda APENAS com 1 a 2 frases curtas de contexto (do que o trecho trata e onde se encaixa no documento), ' \
      'na mesma língua do documento. Não repita o trecho, não comente, não use marcadores.'
  end

  def user_prompt(chunk)
    <<~PROMPT
      <documento>
      #{@document_content}
      </documento>

      <trecho>
      #{chunk}
      </trecho>

      Escreva o contexto curto para situar o trecho no documento.
    PROMPT
  end

  def instrumentation_params(chunk)
    {
      span_name: 'llm.captain.contextual_chunk',
      model: @model,
      temperature: 0,
      feature_name: 'contextual_chunk',
      account_id: @account_id,
      messages: [
        { role: 'system', content: system_prompt },
        { role: 'user', content: user_prompt(chunk) }
      ]
    }
  end
end
