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

  # Classificador de uma resposta que NAO declara numero, em 4 categorias:
  # positive (elogio), negative (insatisfacao), other_topic (o cliente quer tratar de
  # outro assunto, nao avaliar) e neutral (saudacao/ambiguo). Usado para: "adorei" ->
  # promotor, "pessimo" -> detrator, "quero falar do meu pedido" -> atendimento humano.
  # Em duvida -> neutral.
  CLASSIFY_PROMPT = <<~PROMPT
    Voce classifica uma mensagem curta (pt-BR) enviada como resposta a uma pesquisa de
    satisfacao (NPS), quando ela NAO contem um numero de 0 a 10.
    Retorne SOMENTE um JSON {"category": "positive"|"negative"|"other_topic"|"neutral"}.

    Regras:
    - "negative": insatisfacao/reclamacao CLARA sobre o atendimento/produto/empresa
      ("pessimo", "nao gostei", "horrivel", "demorou demais", "ninguem me ajudou").
    - "positive": satisfacao/elogio CLARO ("otimo", "adorei", "excelente", "muito bom",
      "atendimento perfeito", "recomendo").
    - "other_topic": o cliente NAO esta avaliando; quer falar de OUTRO assunto ou pedir
      ajuda com algo novo ("quero falar sobre meu pedido", "tenho outra duvida",
      "preciso de ajuda com...", "gostaria de comprar", "cade meu produto").
    - "neutral": saudacao, agradecimento simples, ou mensagem ambigua/sem intencao clara.
    - Na duvida -> "neutral".
    Responda apenas com o JSON.
  PROMPT

  VALID_CATEGORIES = %w[positive negative other_topic neutral].freeze

  def self.extract(text:, account:)
    new(text: text, account: account).extract
  end

  # 'positive' | 'negative' | 'other_topic' | 'neutral'. 'neutral' em erro/sem chave.
  def self.classify(text:, account:)
    new(text: text, account: account).classify
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

  def classify
    return 'neutral' if @text.blank?
    return 'neutral' if api_key.blank?

    response = client.chat(parameters: classify_parameters)
    content = response.dig('choices', 0, 'message', 'content')
    parse_category(content)
  rescue StandardError => e
    Rails.logger.warn("[NpsSurveys::ScoreLlmParser#classify] #{e.class}: #{e.message}")
    'neutral'
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

  def classify_parameters
    {
      model: model,
      temperature: 0,
      max_tokens: 15,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: CLASSIFY_PROMPT },
        { role: 'user', content: @text.truncate(280) }
      ]
    }
  end

  def parse_category(content)
    return 'neutral' if content.blank?

    value = JSON.parse(content)['category'].to_s.downcase
    VALID_CATEGORIES.include?(value) ? value : 'neutral'
  rescue JSON::ParserError
    'neutral'
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
