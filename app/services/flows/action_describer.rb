# frozen_string_literal: true

# READ-ONLY. Descreve o que um nó `type:"action"` FARIA numa SIMULAÇÃO (dry-run) do
# Flows::SimulationService, SEM NUNCA executá-lo. Garantias de inocuidade por construção:
#   • NÃO instancia o Flows::ActionService nem chama qualquer método de ação (send_message,
#     set_attribute, assign_agent, ai_classify, …) — ele apenas LÊ os action_params do nó.
#   • O único efeito possível é renderizar Liquid ({{contact.name}}) contra a conversa de
#     exemplo, usando os MESMOS drops read-only do envio real (ContactDrop/ConversationDrop/
#     AccountDrop — presenters que só LEEM atributos). Nada é gravado, enviado ou chamado.
#
# Devolve { would: '<frase legível pt-BR>', params_resolved: <params com Liquid resolvido> }.
class Flows::ActionDescriber
  # Verbo condicional ("...aria") por ação — o `would` fica "Verbo: <resumo dos params>". Cobre o
  # vocabulário do motor (Flow::BASE_ACTION_NAMES + as ações enterprise add_sla/assign_ai_agent/
  # ai_classify/ai_generate). Ação fora da lista cai no fallback genérico em #humanize.
  VERBS = {
    'send_message' => 'Enviaria a mensagem',
    'add_private_note' => 'Adicionaria a nota privada',
    'send_attachment' => 'Enviaria anexo',
    'send_webhook_event' => 'Dispararia o webhook para',
    'send_email_to_team' => 'Enviaria e-mail para o time',
    'send_email_transcript' => 'Enviaria a transcrição por e-mail para',
    'send_template' => 'Enviaria o template WhatsApp',
    'set_attribute' => 'Gravaria o atributo',
    'move_funnel_stage' => 'Moveria a conversa de etapa no funil',
    'call_macro' => 'Executaria a macro',
    'send_csat' => 'Dispararia a pesquisa CSAT',
    'add_label' => 'Adicionaria a(s) etiqueta(s)',
    'remove_label' => 'Removeria a(s) etiqueta(s)',
    'assign_agent' => 'Atribuiria ao(s) agente(s)',
    'assign_team' => 'Atribuiria ao time',
    'remove_assigned_team' => 'Removeria o time atribuído',
    'mute_conversation' => 'Silenciaria a conversa',
    'snooze_conversation' => 'Adiaria (snooze) a conversa',
    'resolve_conversation' => 'Resolveria a conversa',
    'open_conversation' => 'Reabriria a conversa',
    'pending_conversation' => 'Marcaria a conversa como pendente',
    'change_status' => 'Mudaria o status para',
    'change_priority' => 'Mudaria a prioridade para',
    'add_sla' => 'Aplicaria a política de SLA',
    'assign_ai_agent' => 'Atribuiria ao agente de IA',
    'ai_classify' => 'Classificaria a conversa via IA',
    'ai_generate' => 'Geraria conteúdo via IA'
  }.freeze

  def initialize(conversation:, account:)
    @conversation = conversation
    @account = account
  end

  def describe(node)
    action = (node || {}).with_indifferent_access
    name = action[:action_name].to_s
    params = deep_render(action[:action_params])
    { would: humanize(name, params), params_resolved: params }
  end

  private

  def humanize(name, params)
    verb = VERBS.fetch(name) { "Executaria a ação '#{name}'" }
    summary = param_summary(params)
    summary.present? ? "#{verb}: #{summary}" : verb
  end

  # Resumo compacto e legível dos params já resolvidos (para o `would`). O detalhe completo vai
  # em params_resolved; aqui truncamos para uma frase curta.
  def param_summary(params)
    first = params.is_a?(Array) ? params.first : params
    summary = if first.is_a?(Hash)
                first.map { |key, value| "#{key}: #{value}" }.join(', ')
              else
                Array(params).compact.join(', ')
              end
    summary.length > 120 ? "#{summary[0, 117]}..." : summary
  end

  # Resolve Liquid em qualquer String dos params, recursivo em Arrays/Hashes. Read-only: os drops
  # só LEEM atributos da conversa/contato/conta.
  def deep_render(value)
    case value
    when Array then value.map { |item| deep_render(item) }
    when Hash then value.transform_values { |item| deep_render(item) }
    when String then render_liquid(value)
    else value
    end
  end

  # Best-effort (paridade com Flows::ActionService#render_liquid): um template malformado devolve
  # o valor cru em vez de derrubar a simulação. `render` (não `render!`) já não levanta em erro
  # de runtime; o rescue cobre erros de parse.
  def render_liquid(value)
    return value unless value.include?('{{')

    Liquid::Template.parse(value).render(liquid_drops)
  rescue StandardError
    value
  end

  def liquid_drops
    {
      'contact' => ContactDrop.new(@conversation.contact),
      'conversation' => ConversationDrop.new(@conversation),
      'account' => AccountDrop.new(@account)
    }
  end
end
