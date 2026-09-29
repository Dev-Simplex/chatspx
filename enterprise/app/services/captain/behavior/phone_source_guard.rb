# Guarda de saída para telefone (CHAT-159): todo telefone que a IA cita precisa ter FONTE no
# atendimento. Caso real (conta 6, conv 42863): o cliente pediu o WhatsApp e a IA respondeu duas
# vezes um número que não existia em lugar nenhum — o certo só vivia no cadastro da unidade, e a
# ferramenta que o traz estava armada e não foi chamada. Regra de prompt é conduta, não trava:
# quando o dado certo não está em nenhum texto que o modelo lê, não chamar a ferramenta produz
# invenção com cara de fato.
#
# Fonte é o que o sistema sabe, nunca o que a própria IA já disse — senão o número inventado no
# primeiro turno se legitimaria no segundo, que foi exatamente o que aconteceu naquela conversa:
#   · telefones das unidades ativas da conta (cadastro);
#   · o próprio telefone do contato;
#   · o que as ferramentas devolveram no atendimento (captain_tool_calls, o mesmo trace da
#     ToolContextNote — só existe onde a conta grava o trace);
#   · mensagens do cliente e de humanos da equipe;
#   · o texto de configuração do assistente (prompt, cenários), que o modelo lê a cada turno.
#
# Opt-in por assistente: `behavior.guards.telefone_sem_fonte = true`. Desligada, nada muda.
class Captain::Behavior::PhoneSourceGuard
  # Telefone brasileiro na resposta: DDI e DDD opcionais, com ou sem o nono dígito, com ou sem
  # separadores. Exige dois blocos de 4 dígitos, o que deixa de fora preço ("520.000"), CEP
  # ("78550-000"), CPF e código de imóvel.
  TELEFONE = /(?<!\d)(?:\+?55[\s.-]?)?(?:\(\s?\d{2}\s?\)\s?|\d{2}[\s.-]?)?(?:9[\s.-]?)?\d{4}[\s.-]?\d{4}(?!\d)/
  # Comparação pelos 8 últimos dígitos: absorve DDI, DDD e o nono dígito, que a IA, o cadastro e
  # o cliente escrevem cada um de um jeito.
  CHAVE = 8
  REMETENTES_DA_IA = %w[Captain::Assistant AgentBot].freeze

  def self.enabled_for?(assistant)
    ActiveModel::Type::Boolean.new.cast((assistant&.behavior || {}).dig('guards', 'telefone_sem_fonte')).present?
  end

  def initialize(assistant:, conversation:, desde: nil)
    @assistant = assistant
    @conversation = conversation
    @desde = desde
  end

  # Telefones da resposta que não têm fonte, como a IA os escreveu.
  def sem_fonte(content)
    citados = content.to_s.scan(TELEFONE).map(&:strip).uniq
    return [] if citados.empty?

    conhecidas = chaves_das_fontes
    citados.reject { |numero| conhecidas.include?(chave(numero)) }
  end

  private

  def chave(numero)
    numero.to_s.gsub(/\D/, '').last(CHAVE)
  end

  def chaves_das_fontes
    numeros = telefones_cadastrados + textos_das_fontes.flat_map { |texto| texto.to_s.scan(TELEFONE) }
    numeros.map { |numero| chave(numero) }.select { |c| c.length == CHAVE }.to_set
  end

  def telefones_cadastrados
    unidades = ::Unit.where(account_id: @conversation.account_id, active: true)
    contato = @conversation.contact
    jid = contato&.custom_attributes&.dig('waha_whatsapp_jid').to_s.split('@').first

    unidades.flat_map { |u| [u.phone, *Array(u.contacts).map { |c| c['phone'] }] } + [contato&.phone_number, jid]
  end

  def textos_das_fontes
    retornos_de_ferramenta + mensagens_de_gente + configuracao_do_assistente
  end

  def retornos_de_ferramenta
    escopo = Captain::ToolCall.for_conversation(@conversation.id)
    escopo = escopo.where('captain_tool_calls.created_at >= ?', @desde) if @desde.present?
    escopo.pluck(:result_preview, :args).flat_map { |preview, args| [preview, args.to_json] }
  end

  def mensagens_de_gente
    @conversation.messages.where(private: false)
                 .where('messages.sender_type IS NULL OR messages.sender_type NOT IN (?)', REMETENTES_DA_IA)
                 .pluck(:content)
  end

  def configuracao_do_assistente
    [@assistant.description, @assistant.config.to_json, @assistant.response_guidelines.to_json,
     @assistant.guardrails.to_json, *@assistant.scenarios.pluck(:instruction)]
  end
end
