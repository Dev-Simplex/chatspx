module Concerns::Agentable
  extend ActiveSupport::Concern

  def agent
    Agents::Agent.new(
      name: agent_name,
      instructions: ->(context) { agent_instructions(context) },
      tools: agent_tools,
      model: agent_model,
      temperature: temperature.to_f || 0.7,
      response_schema: agent_response_schema
    )
  end

  def agent_instructions(context = nil)
    enhanced_context = prompt_context.merge(time_awareness)

    if context
      state = context.context[:state] || {}
      config = state[:assistant_config] || {}
      enhanced_context = enhanced_context.merge(
        conversation: state[:conversation] || {},
        contact: config['feature_contact_attributes'].present? ? state[:contact] : nil,
        campaign: state[:campaign] || {}
      )
    end

    Captain::PromptRenderer.render(template_name, enhanced_context.with_indifferent_access)
  end

  private

  def agent_name
    raise NotImplementedError, "#{self.class} must implement agent_name"
  end

  def template_name
    self.class.name.demodulize.underscore
  end

  def agent_tools
    []  # Default implementation, override if needed
  end

  def agent_model
    raw = account&.captain_assistant_model.presence || LlmConstants::DEFAULT_MODEL
    Llm::Models.runtime_id_for(raw)
  end

  # Injeta data/hora atual e status do horário comercial no contexto do prompt,
  # pra o agente não adivinhar/alucinar horário (ex: dizer "volta segunda" numa quarta).
  def time_awareness
    asst = is_a?(Captain::Assistant) ? self : assistant
    bh = asst.behavior['business_hours'] || {}
    tz = ActiveSupport::TimeZone[bh['timezone'].presence || 'America/Cuiaba'] || ActiveSupport::TimeZone['UTC']
    now = Time.current.in_time_zone(tz)
    dias = %w[domingo segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado]
    inside = Captain::Behavior::BusinessHoursChecker.new(assistant: asst).status == :inside
    {
      current_datetime: "#{dias[now.wday]}, #{now.strftime('%d/%m/%Y às %H:%M')}",
      business_status: inside ? 'dentro do horário comercial, com atendentes disponíveis agora' : 'fora do horário comercial no momento'
    }
  rescue StandardError
    {}
  end

  def agent_response_schema
    Captain::ResponseSchema
  end

  def prompt_context
    raise NotImplementedError, "#{self.class} must implement prompt_context"
  end
end
