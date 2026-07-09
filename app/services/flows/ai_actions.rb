# frozen_string_literal: true

# Nós de IA do motor Flow (Fase 3.2), misturados no Flows::ActionService (mesmo padrão do
# Flows::Compliance). Usam o Captain (a IA nativa do produto) como MOTOR, reusando o serviço
# Captain REAL `Captain::Llm::AssistantChatService` — o mesmo `generate_response` que gera as
# respostas do assistente (assistant/copilot). NÃO inventamos API de LLM: o assistant já carrega
# a config/credencial de LLM da conta (via Llm::Config) e o roteamento de modelo.
#
# São ações ENTERPRISE: só entram no vocabulário via `Enterprise::Flow#allowed_action_names`
# (coerente com assign_ai_agent). O guard `defined?` em #captain_generate as torna um no-op
# seguro num build community — onde a whitelist nem as despacharia.
#
# ANTI-LOOP / CUSTO (plano §5):
#   • Nenhuma das duas invoca sub-flows/macros → NÃO tocam Current.flow_depth; rodam DENTRO do
#     walk já limitado por Flows::RunnerService::MAX_DEPTH, herdando a profundidade corrente.
#     Não há como aprofundar recursão de flow a partir daqui.
#   • ai_classify grava um atributo (sem criar mensagem) → paridade exata com set_attribute;
#     nada re-dispara o motor por mensagem.
#   • ai_generate, ao gravar NOTA, reusa #add_private_note → a mensagem nasce com o marcador
#     `flow_id` (message_content_attributes). O listener descarta mensagens com flow_id
#     (automation_rule_listener#ignore_message_created_event?), então a nota gerada NÃO
#     re-dispara o flow. Ao gravar atributo, mesmo caso do ai_classify.
#   • Guarda de custo: config inválida (assistente/categorias/prompt ausentes) é no-op ANTES de
#     qualquer chamada ao LLM — um nó mal configurado nunca queima crédito Captain.
#
# Depende do host (Flows::ActionService): @account, @conversation e o método add_private_note.
module Flows::AiActions
  private

  # Pede ao Captain para classificar a conversa em UMA de N categorias definidas pelo usuário e
  # grava a categoria escolhida num atributo (custom_attributes por padrão), que um `router`
  # subsequente lê via condição. action_params =
  #   [{ assistant_id, prompt?, categories: [...], target?('conversation'|'contact'),
  #      store?('custom'|'additional'), key }]
  def ai_classify(action_params)
    config = action_params[0].to_h.with_indifferent_access
    categories = normalized_categories(config)
    assistant = captain_assistant(config[:assistant_id])
    return if categories.blank? || config[:key].blank? || assistant.nil?

    answer = ai_text(captain_generate(assistant, classify_instruction(config[:prompt], categories)))
    return if answer.blank?

    store_ai_result(target: config[:target], store: config[:store], key: config[:key].to_s, value: match_category(answer, categories))
  end

  # Pede ao Captain um texto (ex.: rascunho de resposta) e grava numa NOTA interna (padrão) ou
  # num atributo. action_params =
  #   [{ assistant_id, prompt, target?('note'|'attribute'),
  #      attribute_target?('conversation'|'contact'), store?('custom'|'additional'), key? }]
  def ai_generate(action_params)
    config = action_params[0].to_h.with_indifferent_access
    prompt = config[:prompt].to_s.strip
    assistant = captain_assistant(config[:assistant_id])
    return if prompt.blank? || assistant.nil?

    text = ai_text(captain_generate(assistant, generate_instruction(prompt)))
    return if text.blank?

    if config[:target].to_s == 'attribute'
      store_ai_result(target: config[:attribute_target], store: config[:store], key: config[:key].to_s, value: text)
    else
      add_private_note([text]) # nota interna carregando o marcador flow_id (anti-loop)
    end
  end

  # Normaliza a lista de categorias do usuário: strings limpas, sem vazias/duplicadas.
  def normalized_categories(config)
    Array(config[:categories]).map { |category| category.to_s.strip }.reject(&:blank?).uniq
  end

  # Resolve o assistente Captain da conta. nil (blank/id inexistente) → o caller vira no-op,
  # nunca "chuta" um assistente default (evita disparar IA numa conversa por engano).
  def captain_assistant(assistant_id)
    return if assistant_id.blank?

    @account.captain_assistants.find_by(id: assistant_id)
  end

  # Chama o serviço Captain REAL (mesmo motor das respostas do assistente). `defined?` porque a
  # classe é enterprise; qualquer erro/serviço ausente → nil (no-op), sem derrubar o passo.
  def captain_generate(assistant, instruction)
    return unless defined?(Captain::Llm::AssistantChatService)

    Captain::Llm::AssistantChatService
      .new(assistant: assistant, conversation: @conversation.reload)
      .generate_response(additional_message: instruction)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    nil
  end

  # generate_response devolve o Hash já parseado ({response, reasoning} ou {content} de
  # fallback); pode vir String em caminhos de fallback. Extrai o texto útil.
  def ai_text(response)
    case response
    when String
      response.strip
    when Hash
      hash = response.with_indifferent_access
      (hash[:response] || hash[:content] || hash[:text]).to_s.strip
    else
      ''
    end
  end

  def classify_instruction(prompt, categories)
    <<~PROMPT.strip
      #{prompt}
      Classifique a conversa abaixo em UMA destas categorias: #{categories.join(', ')}.
      Responda com APENAS o nome exato da categoria, sem explicação nem pontuação.

      Conversa:
      #{@conversation.to_llm_text}
    PROMPT
  end

  def generate_instruction(prompt)
    <<~PROMPT.strip
      #{prompt}

      Conversa (contexto):
      #{@conversation.to_llm_text}
    PROMPT
  end

  # Casa a resposta livre do modelo com uma das categorias canônicas: match exato
  # (case-insensitive), depois substring; se nada casar, devolve o texto cru (observável).
  def match_category(answer, categories)
    down = answer.downcase
    categories.find { |category| category.casecmp?(answer) } ||
      categories.find { |category| down.include?(category.downcase) } ||
      answer
  end

  # Grava no custom_attributes (padrão) ou additional_attributes da conversa/contato — mesmo
  # mecanismo do set_attribute. Um router/condição posterior lê o valor.
  def store_ai_result(target:, store:, key:, value:)
    return if key.blank?

    record = target.to_s == 'contact' ? @conversation.contact : @conversation.reload
    return if record.blank?

    bag = store.to_s == 'additional' ? :additional_attributes : :custom_attributes
    current = record.public_send(bag) || {}
    record.update!(bag => current.merge(key => value))
  end
end
