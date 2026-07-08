# frozen_string_literal: true

# Fallback de PARSING (nao de inferencia) para a nota de NPS.
#
# Quando o regex do NpsSurveys::ScoreValidator falha mas a mensagem parece uma
# tentativa curta de responder o NPS (ex.: "dez", "nota nove", "uns 8"), este
# servico chama o LLM SO para EXTRAIR um inteiro 0-10 EXPLICITO do texto.
#
# Regras (deliberadas, baseadas na pesquisa do plano de NPS):
#   - NUNCA inferir nota a partir de sentimento ("pessimo" -> 2). Isso enviesa e
#     erra mais nos detratores. Se o cliente nao declarou um numero, retorna nil
#     e o texto segue como comentario.
#   - Chamada minima (temperatura 0, poucos tokens, resposta em JSON estrito),
#     so no caminho de falha do regex e atras de um toggle por inbox.
#   - Falha (sem chave, erro de rede, JSON invalido) -> nil, sem quebrar o fluxo.
class NpsSurveys::ScoreLlmParser
  DEFAULT_MODEL = 'gpt-4o-mini'

  SYSTEM_PROMPT = <<~PROMPT
    Voce extrai a NOTA de uma pesquisa NPS (0 a 10) de uma mensagem curta em portugues.
    Retorne SOMENTE um JSON no formato {"score": N} onde N e um inteiro de 0 a 10,
    ou {"score": null} se a mensagem NAO declara explicitamente um numero de 0 a 10.

    Regras rigidas:
    - Considere apenas numeros EXPLICITOS, em digito ("8", "10") ou por extenso
      ("dez"->10, "nove"->9, "oito"->8, "zero"->0). "uns 8", "nota 7", "acho que 9" contam.
    - NAO INFIRA a partir de sentimento ou elogio/reclamacao. "otimo", "pessimo",
      "adorei", "horrivel" SEM numero -> {"score": null}.
    - Numero fora de 0-10 (ex.: "11", "100", "-1") -> {"score": null}.
    - Se houver mais de um numero, use o que representa a nota; em duvida -> {"score": null}.
    Responda apenas com o JSON, sem texto extra.
  PROMPT

  # Classificador de SENTIMENTO (separado do parsing de nota). So responde se a
  # mensagem, SEM declarar numero, expressa insatisfacao CLARA com o atendimento/
  # empresa. Usado para tratar "pessimo, nao gostei" como detrator. Nunca marca
  # como insatisfeito por elogio/neutro; em duvida -> false.
  SENTIMENT_PROMPT = <<~PROMPT
    Voce classifica o SENTIMENTO de uma mensagem curta (pt-BR) enviada como resposta
    a uma pesquisa de satisfacao, quando ela NAO contem um numero de 0 a 10.
    Retorne SOMENTE um JSON {"dissatisfied": true|false}.

    Regras:
    - true SOMENTE quando ha insatisfacao/reclamacao CLARA sobre o atendimento,
      produto ou empresa ("pessimo", "nao gostei", "horrivel", "demorou demais",
      "ninguem me ajudou", "muito ruim").
    - false para elogio ("otimo", "adorei"), neutro, saudacao, pergunta, ou
      mensagem ambigua/sem opiniao clara.
    - Na duvida -> false.
    Responda apenas com o JSON.
  PROMPT

  def self.extract(text:, account:)
    new(text: text, account: account).extract
  end

  # true quando a mensagem expressa insatisfacao clara (sem numero). false em erro/sem chave.
  def self.dissatisfied?(text:, account:)
    new(text: text, account: account).dissatisfied?
  end

  def initialize(text:, account:)
    @text = text.to_s
    @account = account
  end

  def extract
    return nil if @text.blank?
    return nil if api_key.blank?

    response = client.chat(parameters: chat_parameters)
    content = response.dig('choices', 0, 'message', 'content')
    parse_score(content)
  rescue StandardError => e
    Rails.logger.warn("[NpsSurveys::ScoreLlmParser] #{e.class}: #{e.message}")
    nil
  end

  def dissatisfied?
    return false if @text.blank?
    return false if api_key.blank?

    response = client.chat(parameters: sentiment_parameters)
    content = response.dig('choices', 0, 'message', 'content')
    parse_dissatisfied(content)
  rescue StandardError => e
    Rails.logger.warn("[NpsSurveys::ScoreLlmParser#dissatisfied?] #{e.class}: #{e.message}")
    false
  end

  private

  def client
    OpenAI::Client.new(access_token: api_key)
  end

  def chat_parameters
    {
      model: model,
      temperature: 0,
      max_tokens: 20,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        { role: 'user', content: @text.truncate(280) }
      ]
    }
  end

  def sentiment_parameters
    {
      model: model,
      temperature: 0,
      max_tokens: 15,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: SENTIMENT_PROMPT },
        { role: 'user', content: @text.truncate(280) }
      ]
    }
  end

  def parse_dissatisfied(content)
    return false if content.blank?

    ActiveModel::Type::Boolean.new.cast(JSON.parse(content)['dissatisfied']) || false
  rescue JSON::ParserError
    false
  end

  def parse_score(content)
    return nil if content.blank?

    parsed = JSON.parse(content)
    score = parsed['score']
    return nil if score.nil?

    score = Integer(score, exception: false)
    return nil if score.nil?
    return nil unless score.between?(0, 10)

    score
  rescue JSON::ParserError
    nil
  end

  # Chave: reaproveita a integracao OpenAI ja existente no fork (Captain), com
  # fallbacks para chave por conta ou ENV. Nao depende de nenhum modulo enterprise.
  def api_key
    return @api_key if defined?(@api_key)

    @api_key = installation_key.presence || account_key.presence || ENV['OPENAI_API_KEY'].presence
  end

  def installation_key
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
  rescue StandardError
    nil
  end

  def account_key
    @account&.settings&.dig('openai_api_key')
  end

  def model
    installation_model.presence || DEFAULT_MODEL
  end

  def installation_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value
  rescue StandardError
    nil
  end
end
