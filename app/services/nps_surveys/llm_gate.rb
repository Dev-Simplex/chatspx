# frozen_string_literal: true

# Fonte unica dos predicados que decidem SE o LLM sera consultado sobre uma resposta
# de NPS sem nota em digito. Espelha o que o NpsSurveys::ScoreValidator ja faz para o
# regex: os dois lados que decidem a mesma pergunta compartilham o mesmo objeto.
#
# Quem consulta:
# - NpsSurveys::ResponseBuilder (assincrono) — de fato chama o ScoreLlmParser.
# - NpsSurveys::ReopenGuard (sincrono, no after_create_commit da Message) — segura o
#   reopen quando o builder VAI chamar o LLM, deferindo a decisao a ele.
#
# Assimetria entre os dois = a conversa reabre e dispara automacoes/flows antes do NPS
# reconhecer a resposta (ex.: "excelente" nao tem digito: o regex nao ve, o LLM ve).
# Por isso os limites e toggles moram aqui, e nao duplicados em cada lado.
class NpsSurveys::LlmGate
  # Sentimento: so classifica mensagem nao-vazia de tamanho de feedback,
  # evitando gasto em mensagens muito longas/estranhas.
  SENTIMENT_MAX_LENGTH = 280

  # Parse por extenso: mensagem curta que contenha um digito ou um numeral
  # escrito (0-10). Evita gastar chamada em conversa normal.
  GPT_PARSE_MAX_LENGTH = 40
  NUMBER_WORDS = /\b(zero|um|uma|dois|duas|tr[êe]s|quatro|cinco|seis|sete|oito|nove|dez)\b/i

  class << self
    # O que o ReopenGuard consulta: se o builder vai perguntar ao LLM sobre esta
    # mensagem, a decisao (e o reopen) e dele.
    def will_attempt?(inbox:, text:)
      sentiment_candidate?(inbox: inbox, text: text) || gpt_parse_candidate?(inbox: inbox, text: text)
    end

    def sentiment_candidate?(inbox:, text:)
      return false unless sentiment_detractor_enabled?(inbox)

      normalized = NpsSurveys::ScoreValidator.normalize(text)
      normalized.present? && normalized.length <= SENTIMENT_MAX_LENGTH
    end

    def gpt_parse_candidate?(inbox:, text:)
      return false unless gpt_parse_enabled?(inbox)

      normalized = NpsSurveys::ScoreValidator.normalize(text)
      return false if normalized.blank?
      return false if normalized.length > GPT_PARSE_MAX_LENGTH

      normalized.match?(/\d/) || normalized.match?(NUMBER_WORDS)
    end

    def sentiment_detractor_enabled?(inbox)
      truthy_config?(nps_config(inbox)['sentiment_detractor_enabled'])
    end

    def gpt_parse_enabled?(inbox)
      truthy_config?(nps_config(inbox)['gpt_parse_enabled'])
    end

    private

    def nps_config(inbox)
      inbox&.nps_config || {}
    end

    def truthy_config?(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end
  end
end
