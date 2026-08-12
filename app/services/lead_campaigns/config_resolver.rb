# Resolve, por campanha, a configuração que o hook de captação aplica ao lead.
#
# Espelha o `hook_setting` de `Meta::LeadAds::CreateConversationService`: o valor do
# override da campanha quando presente, senão o global do hook. Precisa continuar
# espelhando — o valor da tela está em mostrar o que a engine REALMENTE usa; um chute
# diferente aqui vira relatório que mente.
#
# Só lê. É consumido pelo viewer de campanhas (`Api::V1::Accounts::LeadCampaignsController`).
class LeadCampaigns::ConfigResolver
  # Apps de captação de lead por formulário. Todos entregam pela mesma engine e por
  # isso compartilham o formato de settings — inclusive `campaign_overrides`.
  INTAKE_APP_IDS = %w[meta_lead_ads site_leads].freeze

  # App cujos leads carregam id de campanha (anúncio). Os demais (formulário de site)
  # entregam lead sem campanha nenhuma — é o que separa um hook do outro quando a
  # conta tem mais de um.
  CAMPAIGN_APP_ID = 'meta_lead_ads'.freeze

  INDEFINIDA = { hook_id: nil, origem: 'indefinido', sobrescritos: [] }.freeze

  def initialize(account)
    @account = account
  end

  def any?
    hooks.any?
  end

  # Ids de campanha que alguém configurou explicitamente — inclusive as que não
  # trouxeram lead nenhum no período.
  def campanhas_configuradas
    hooks.flat_map { |hook| overrides(hook).keys }.uniq
  end

  def para(campaign_id)
    hook = hook_para(campaign_id)
    return INDEFINIDA.dup if hook.nil?

    override = overrides(hook)[campaign_id.to_s] || {}
    {
      hook_id: hook.id,
      origem: override.present? ? 'override' : 'padrao',
      sobrescritos: override.keys.sort,
      bloqueada: bloqueada?(hook, campaign_id)
    }.merge(valores(hook, override))
  end

  def hooks_payload
    hooks.map { |hook| hook_payload(hook) }
  end

  private

  # Hook desabilitado continua na lista: ele não roteia mais nada, mas é a configuração
  # dele que explica os leads que já entraram no período.
  def hooks
    @hooks ||= @account.hooks.where(app_id: INTAKE_APP_IDS).order(:id).to_a
  end

  def settings(hook)
    hook.settings || {}
  end

  # ------------------------------------------------------------------ valores

  def valores(hook, override)
    resolve = resolvedor(hook, override)
    template = resolve.call('whatsapp_template_name')
    {
      template: template,
      template_sincronizado: template_sincronizado?(hook, template),
      template_imovel: resolve.call('imovel_template_name'),
      lead_tipo: resolve.call('lead_tipo'),
      agente: agent_bots[resolve.call('assign_agent_bot_id').to_i],
      time: times[resolve.call('assign_team_id').to_i]
    }
  end

  def resolvedor(hook, override)
    configuracao = settings(hook)
    ->(chave) { override[chave].to_s.strip.presence || configuracao[chave].to_s.strip.presence }
  end

  # ------------------------------------------------------------------- hooks

  # Qual hook responde por esta campanha. Determinístico, e sem chutar quando a conta
  # tem mais de um hook do mesmo tipo:
  #   1. o hook que tem override para o id;
  #   2. o hook cujo allowlist inclui o id;
  #   3. campanha COM id → o único hook de campanha da conta;
  #      campanha SEM id → o único hook de captação sem campanha (ex.: formulário de site);
  #   4. nada resolveu → indefinido (a tela mostra o volume e omite a configuração).
  def hook_para(campaign_id)
    id = campaign_id.to_s
    return unico(hooks.reject { |hook| hook.app_id == CAMPAIGN_APP_ID }) if id.blank?

    hook_da_campanha(id)
  end

  def hook_da_campanha(id)
    com_override = hooks.find { |hook| overrides(hook).key?(id) }
    return com_override if com_override

    na_allowlist = hooks.select { |hook| allowlist(hook).include?(id) }
    return na_allowlist.first if na_allowlist.size == 1

    unico(hooks.select { |hook| hook.app_id == CAMPAIGN_APP_ID })
  end

  def unico(lista)
    lista.size == 1 ? lista.first : nil
  end

  def overrides(hook)
    valor = settings(hook)['campaign_overrides']
    valor.is_a?(Hash) ? valor.select { |_id, config| config.is_a?(Hash) } : {}
  end

  def allowlist(hook)
    bruto = settings(hook)['allowed_campaign_ids']
    lista = bruto.is_a?(Array) ? bruto : bruto.to_s.split(',')
    lista.map { |id| id.to_s.strip }.reject(&:blank?)
  end

  # Allowlist não-vazia que não inclui a campanha = lead ignorado já na entrada. É
  # config, e explica sozinha uma campanha com zero lead.
  def bloqueada?(hook, campaign_id)
    lista = allowlist(hook)
    return false if lista.empty? || campaign_id.blank?

    lista.exclude?(campaign_id.to_s)
  end

  # --------------------------------------------------------------- templates

  # O template configurado existe entre os aprovados que o canal já sincronizou? Quando
  # não existe, a abertura simplesmente não sai — e hoje isso só aparece no log.
  # `nil` = o canal não expõe templates, então não dá para afirmar nada.
  def template_sincronizado?(hook, nome)
    return nil if nome.blank?

    aprovados = templates_do_canal(hook)
    aprovados&.include?(nome)
  end

  def templates_do_canal(hook)
    @templates_do_canal ||= {}
    return @templates_do_canal[hook.id] if @templates_do_canal.key?(hook.id)

    @templates_do_canal[hook.id] = buscar_templates(hook)
  end

  def buscar_templates(hook)
    canal = inbox_do(hook)&.channel
    # `try`: só o canal WhatsApp guarda templates sincronizados; os demais não respondem.
    lista = canal.try(:message_templates)
    return nil unless lista.is_a?(Array)

    lista.filter_map { |template| template['name'] if template.is_a?(Hash) }
  rescue StandardError
    nil
  end

  def inbox_do(hook)
    Inbox.find_by(account_id: @account.id, id: settings(hook)['target_inbox_id'])
  end

  # ------------------------------------------------------------ nomes (lote)

  def agent_bots
    @agent_bots ||= indexar(AgentBot.where(id: ids_configurados('assign_agent_bot_id')))
  end

  def times
    @times ||= indexar(@account.teams.where(id: ids_configurados('assign_team_id')))
  end

  def indexar(escopo)
    escopo.pluck(:id, :name).to_h { |id, nome| [id, { id: id, nome: nome }] }
  rescue StandardError
    {}
  end

  # Todos os ids daquela chave que aparecem no hook ou em qualquer override dele, para
  # resolver nome de agente e de time numa consulta só.
  def ids_configurados(chave)
    brutos = hooks.flat_map do |hook|
      [settings(hook)[chave]] + overrides(hook).values.map { |config| config[chave] }
    end
    brutos.filter_map { |id| id.presence&.to_i }.uniq
  end

  # ------------------------------------------------------------------ resumo

  def hook_payload(hook)
    configuracao = settings(hook)
    {
      id: hook.id,
      app_id: hook.app_id,
      habilitado: hook.enabled?,
      pagina: configuracao['page_name'].presence || configuracao['site_name'].presence,
      inbox: inbox_do(hook)&.slice(:id, :name),
      template: configuracao['whatsapp_template_name'].presence,
      agente: agent_bots[configuracao['assign_agent_bot_id'].to_i],
      time: times[configuracao['assign_team_id'].to_i],
      campanhas_com_override: overrides(hook).keys.size,
      allowlist: allowlist(hook)
    }
  end
end
