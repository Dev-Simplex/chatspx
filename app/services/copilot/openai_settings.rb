class Copilot::OpenaiSettings
  DEFAULT_MODEL = 'gpt-4o-mini'.freeze
  ADVANCED_MODEL = 'gpt-4o'.freeze
  VISION_MODEL = 'gpt-4o-mini'.freeze

  CHAT_MODELS_PRICING = {
    'gpt-4o-mini' => { input: 0.15, output: 0.60 },
    'gpt-4o' => { input: 2.50, output: 10.00 },
    'gpt-4-turbo' => { input: 10.00, output: 30.00 },
    'o1-mini' => { input: 3.00, output: 12.00 },
    'o1-preview' => { input: 15.00, output: 60.00 }
  }.freeze

  WHISPER_COST_PER_MINUTE = 0.006

  class << self
    # A chave da conta manda, e o ENV é o segundo. O terceiro degrau é a chave GLOBAL do
    # Captain, e ele existe porque sem ele a descrição de mídia morria em silêncio numa
    # instalação inteira.
    #
    # Conv 30328 (Tozi, 08/09): a cliente respondeu a stories e a IA respondeu no escuro —
    # "vi que você mandou uma imagem" — e depois cutucou cinco vezes. A causa não era o
    # pipeline de vídeo, que está deployado e funciona (extraí três quadros do story real):
    # era a chamada de visão voltando 401. E o 401 não era chave ruim, era chave AUSENTE: as
    # duas chaves de OpenAI que a box tem respondem HTTP 200 quando testadas, mas nenhuma
    # delas mora nos dois lugares que este método lia. O header saía com "Bearer " vazio.
    #
    # `CAPTAIN_OPEN_AI_API_KEY` é a mesma chave que o runner do Captain já usa para todo o
    # resto do produto nessa instalação, então cair nela não amplia acesso nem cria credencial
    # nova — só para de procurar num lugar onde ninguém a guarda. Quem quiser isolar o custo
    # por conta continua podendo, e a chave da conta continua tendo precedência.
    def api_key(account)
      account_key = account&.settings&.dig('openai_api_key').to_s.strip
      env_key = ENV.fetch('OPENAI_API_KEY', nil).to_s.strip
      account_key.presence || env_key.presence || captain_global_key(account)
    end

    # A global do Captain só vale para quem de fato USA o Captain. A justificativa deste degrau
    # é que ela "é a mesma chave que o runner do Captain já usa nessa instalação" — e essa frase
    # só é verdadeira onde há agente cadastrado.
    #
    # Sem esta guarda, medido na PRODUCAO em 09/09/2026 na hora seguinte ao deploy: as contas 5
    # e 85, que não têm agente nenhum, passaram a mandar o conteúdo da última mensagem do
    # CLIENTE para a OpenAI toda vez que um atendente abria uma conversa. A sugestão fantasma
    # dispara sozinha — watcher em `lastIncomingMessage.id` com `immediate: true` no ReplyBox —,
    # sem clique e sem flag de feature. Foram 12 chamadas em uma hora, em conta que nunca ligou
    # IA nenhuma. O custo era irrisório; o problema era o dado saindo.
    #
    # A régua é a MESMA do painel de Agentes IA (`has_ai_agents` = `captain_assistants.exists?`)
    # e NÃO a flag `captain_integration*`: as 10 contas da PRODUCAO têm a flag ligada, então ela
    # não distingue quem usa de quem não usa.
    def captain_global_key(account = nil)
      return nil unless usa_captain?(account)

      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value.to_s.strip.presence
    rescue StandardError => e
      # Config ausente ou banco fora não pode derrubar quem só queria saber se há chave.
      Rails.logger.warn("[OpenaiSettings] chave global do Captain indisponível: #{e.message}")
      nil
    end

    # Conta ausente é contexto de sistema (job sem tenant): ali a global continua valendo.
    # `respond_to?` porque `captain_assistants` mora no overlay Enterprise e este arquivo é OSS.
    def usa_captain?(account)
      return true if account.nil?

      account.respond_to?(:captain_assistants) && account.captain_assistants.exists?
    end

    def default_model(account)
      account&.settings&.dig('openai_model_default').to_s.strip.presence || DEFAULT_MODEL
    end

    def advanced_model(account)
      account&.settings&.dig('openai_model_advanced').to_s.strip.presence || ADVANCED_MODEL
    end

    # Modelo de visao (descricao de midia) tem chave PROPRIA por conta, separada do
    # `openai_model_default`: o default de chat pode ser trocado por um modelo sem visao
    # e a descricao quebraria junto, sem ninguem relacionar uma coisa com a outra.
    def vision_model(account)
      account&.settings&.dig('openai_model_vision').to_s.strip.presence || VISION_MODEL
    end

    def log_chat_usage(service:, account:, model:, response:)
      usage = response.is_a?(Hash) ? response['usage'] : nil
      return if usage.blank?

      tokens_in = usage['prompt_tokens'].to_i
      tokens_out = usage['completion_tokens'].to_i
      cost = chat_cost(model, tokens_in, tokens_out)
      Rails.logger.info(
        "[OpenAI::Telemetry] service=#{service} account_id=#{account&.id || 'global'} model=#{model} " \
        "tokens_in=#{tokens_in} tokens_out=#{tokens_out} cost_usd=#{format('%.6f', cost)}"
      )
    end

    def log_audio_usage(service:, account:, duration_seconds:)
      cost = (duration_seconds.to_f / 60.0) * WHISPER_COST_PER_MINUTE
      Rails.logger.info(
        "[OpenAI::Telemetry] service=#{service} account_id=#{account&.id || 'global'} model=whisper-1 " \
        "duration_s=#{duration_seconds.to_i} cost_usd=#{format('%.6f', cost)}"
      )
    end

    def chat_cost(model, tokens_in, tokens_out)
      pricing = CHAT_MODELS_PRICING[model] || CHAT_MODELS_PRICING[DEFAULT_MODEL]
      ((tokens_in * pricing[:input]) + (tokens_out * pricing[:output])) / 1_000_000.0
    end
  end
end
