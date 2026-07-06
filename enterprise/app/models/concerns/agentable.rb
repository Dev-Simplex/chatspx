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

    return split_instructions_for_cache(enhanced_context) if prompt_cache_system_enabled?

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
    status =
      if inside
        'dentro do horário comercial, com atendentes disponíveis agora'
      else
        reopen = next_business_opening(bh, now)
        if reopen.nil?
          'fora do horário comercial no momento'
        elsif reopen.to_date == now.to_date
          "em pausa no momento (fora do horário), mas os atendentes voltam HOJE às #{reopen.strftime('%H:%M')} — o retorno é hoje à tarde, não amanhã"
        elsif reopen.to_date == now.to_date + 1
          "fechado no momento; os atendentes voltam amanhã (#{dias[reopen.wday]}) às #{reopen.strftime('%H:%M')}"
        else
          "fechado no momento; os atendentes voltam #{dias[reopen.wday]} às #{reopen.strftime('%H:%M')}"
        end
      end
    {
      current_datetime: "#{dias[now.wday]}, #{now.strftime('%d/%m/%Y às %H:%M')}",
      business_status: status,
      business_hours_text: business_hours_text(bh)
    }
  rescue StandardError
    {}
  end

  # Horário de funcionamento em texto, montado a partir da agenda do config da
  # conta (business_hours). Agrupa dias com a mesma faixa ("segunda a sexta, das
  # 7h30 às 11h30 e das 13h30 às 17h30; sábado, das 9h às 11h30"). Assim cada
  # cliente/assistente injeta o SEU horário do banco — sem hardcode no prompt.
  def business_hours_text(bh)
    return nil unless bh['enabled']

    sched = bh['schedule'] || []
    return nil if sched.blank?

    dias = %w[domingo segunda terça quarta quinta sexta sábado]
    ordem = [1, 2, 3, 4, 5, 6, 0]
    sig = ordem.index_with do |d|
      entry = sched.find { |e| e['day'] == d }
      Array(entry && entry['ranges']).filter_map do |r|
        next if r['start'].blank? || r['end'].blank?

        "das #{format_hora(r['start'])} às #{format_hora(r['end'])}"
      end
    end
    partes = []
    i = 0
    while i < ordem.size
      d = ordem[i]
      if sig[d].empty?
        i += 1
        next
      end
      j = i
      j += 1 while j + 1 < ordem.size && sig[ordem[j + 1]] == sig[d]
      faixa = sig[d].join(' e ')
      partes << (i == j ? "#{dias[d]}, #{faixa}" : "#{dias[ordem[i]]} a #{dias[ordem[j]]}, #{faixa}")
      i = j + 1
    end
    partes.presence && partes.join('; ')
  end

  def format_hora(hhmm)
    h, m = hhmm.split(':').map(&:to_i)
    m.zero? ? "#{h}h" : format('%<h>dh%<m>02d', h: h, m: m)
  end

  # Próximo horário de abertura a partir de agora (varre o dia de hoje e os
  # próximos, respeitando a agenda). Serve pra distinguir pausa do almoço
  # ("volta hoje à tarde") de fim de expediente ("volta amanhã").
  def next_business_opening(bh, now)
    schedule = bh['schedule'] || []
    return nil if schedule.blank?

    (0..7).each do |offset|
      day = now + offset.days
      entry = schedule.find { |d| d['day'] == day.wday }
      next if entry.blank?

      (entry['ranges'] || []).each do |range|
        next if range['start'].blank?

        hours, minutes = range['start'].split(':').map(&:to_i)
        start_at = day.change(hour: hours, min: minutes, sec: 0)
        return start_at if start_at > now
      end
    end
    nil
  end

  # Chaves de contexto que MUDAM durante a conversa (data/hora com resolucao de
  # minuto + estado da conversa/contato/campanha, incluindo custom_attributes que
  # as tools escrevem mid-conversa). Precisam ficar FORA do bloco cacheado.
  VOLATILE_PROMPT_KEYS = %w[current_datetime business_status conversation contact campaign].freeze

  # Prompt caching (Fase 2): separa o prefixo ESTAVEL do prompt (identidade,
  # persona, regras, guardrails, cenarios) do VOLATIL (data/hora + contexto da
  # conversa) e devolve dois blocos de system, com cache_control so no estavel.
  # Assim o pedaco grande e constante entra no cache da Anthropic e os turnos
  # seguintes pagam 0.1x nele. So roda com SPX_PROMPT_CACHE_SYSTEM=1.
  #
  # Fail-safe: se qualquer coisa falhar (ex: Content::Raw ausente em outra versao
  # do ruby_llm), cai no render inteiro de sempre — nunca quebra a resposta.
  def split_instructions_for_cache(enhanced_context)
    ctx = enhanced_context.with_indifferent_access
    stable_text = Captain::PromptRenderer.render(template_name, ctx.except(*VOLATILE_PROMPT_KEYS))
    volatile_text = Captain::PromptRenderer.render('runtime_context', ctx.slice(*VOLATILE_PROMPT_KEYS)).strip

    blocks = [{ type: 'text', text: stable_text, cache_control: { type: 'ephemeral' } }]
    blocks << { type: 'text', text: volatile_text } if volatile_text.present?
    RubyLLM::Content::Raw.new(blocks)
  rescue StandardError => e
    Rails.logger.warn("[prompt-cache] split de system falhou, usando prompt inteiro: #{e.class}: #{e.message}")
    Captain::PromptRenderer.render(template_name, enhanced_context.with_indifferent_access)
  end

  # Opt-in por CONTA (multi-tenant): liga a Fase 2 do caching so nas contas que
  # setarem custom_attributes['prompt_cache_system']=true. Fallback global via ENV
  # SPX_PROMPT_CACHE_SYSTEM pra teste. Default (nenhum dos dois) = OFF.
  def prompt_cache_system_enabled?
    asst = is_a?(Captain::Assistant) ? self : assistant
    per_account = asst&.account&.custom_attributes&.dig('prompt_cache_system')
    return ActiveModel::Type::Boolean.new.cast(per_account) unless per_account.nil?

    ActiveModel::Type::Boolean.new.cast(ENV.fetch('SPX_PROMPT_CACHE_SYSTEM', nil))
  end

  def agent_response_schema
    Captain::ResponseSchema
  end

  def prompt_context
    raise NotImplementedError, "#{self.class} must implement prompt_context"
  end
end
