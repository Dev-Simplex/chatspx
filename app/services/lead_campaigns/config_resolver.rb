# Resolve, por campanha, a configuração que o hook de captação aplica ao lead.
#
# Espelha o `hook_setting` de `Meta::LeadAds::CreateConversationService`: o valor do
# override da campanha quando presente, senão o global do hook. Precisa continuar
# espelhando — o valor da tela está em mostrar o que a engine REALMENTE usa; um chute
# diferente aqui vira relatório que mente.
#
# Só lê. É consumido pelo viewer de campanhas (`Api::V1::Accounts::LeadCampaignsController`)
# e pela escrita do roteamento (`LeadCampaigns::RoutingUpdater`), que resolve por aqui o
# hook e a configuração vigente antes de validar a mudança.
class LeadCampaigns::ConfigResolver
  # Apps de captação de lead por formulário. Todos entregam pela mesma engine e por
  # isso compartilham o formato de settings — inclusive `campaign_overrides`.
  INTAKE_APP_IDS = %w[meta_lead_ads site_leads].freeze

  # App cujos leads carregam id de campanha (anúncio). Os demais (formulário de site)
  # entregam lead sem campanha nenhuma — é o que separa um hook do outro quando a
  # conta tem mais de um.
  CAMPAIGN_APP_ID = 'meta_lead_ads'.freeze

  # Autoria da última edição, gravada dentro do override pela tela. Começa com `_` para
  # não se confundir com configuração: a engine nunca lê estas chaves, e elas não contam
  # como "esta campanha sobrescreve algo".
  METADADO = /\A_/

  # O mesmo default do envio: quem valida tem que assumir o idioma que a engine assume.
  DEFAULT_LOCALE = Meta::LeadAds::CreateConversationService::DEFAULT_TEMPLATE_LOCALE

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

    bruto = overrides(hook)[campaign_id.to_s] || {}
    override = configuracao_do_override(bruto)
    {
      hook_id: hook.id,
      origem: override.present? ? 'override' : 'padrao',
      sobrescritos: override.keys.sort,
      bloqueada: bloqueada?(hook, campaign_id),
      editavel: editavel?(hook),
      atualizado_por: bruto['_atualizado_por'].presence,
      atualizado_em: bruto['_atualizado_em'].presence
    }.merge(valores(hook, override))
  end

  def hooks_payload
    hooks.map { |hook| hook_payload(hook) }
  end

  # Quem responde por esta campanha, para a escrita saber ONDE gravar o override. Público
  # porque a validação precisa exatamente do mesmo hook que a leitura mostra na tela —
  # resolver de outro jeito seria salvar num lugar e exibir outro.
  def hook_de(campaign_id)
    hook_para(campaign_id)
  end

  def inbox_de(hook)
    inbox_do(hook)
  end

  def catalogo_de(hook)
    catalogos[hook.id] ||= LeadCampaigns::TemplateCatalog.new(inbox_do(hook))
  end

  # As escolhas que a tela pode oferecer para este hook. Templates saem do próprio canal
  # (aprovados e sincronizados); agente e time, da conta. Vai junto do resumo do hook, que
  # já é payload de admin — é a mesma informação de roteamento.
  def opcoes_de(hook)
    {
      inbox: inbox_do(hook)&.slice(:id, :name),
      template_editavel: editavel?(hook),
      templates: catalogo_de(hook).aprovados,
      campos: Meta::LeadAds::CreateConversationService::BODY_FIELDS,
      agentes: AgentBot.accessible_to(@account).order(:name).map { |bot| agente_payload(bot, hook) },
      times: @account.teams.order(:name).map { |time| { id: time.id, nome: time.name } }
    }
  end

  # "Existe na conta" não é "a inbox aceita": espelho de IA não elegível à inbox alvo é
  # recusado pelo `Conversations::AssignmentService` em SILÊNCIO — a conversa entra sem
  # ninguém e a configuração parece certa na tela. Regra única: a tela oferece por aqui e
  # a escrita recusa por aqui.
  def agente_elegivel?(bot, hook)
    return true unless bot.captain?

    inbox = inbox_do(hook)
    inbox.present? && inbox.captain_assistants.exists?(id: bot.captain_assistant_id)
  rescue StandardError
    false
  end

  private

  def catalogos
    @catalogos ||= {}
  end

  # Template só entra em jogo em inbox Cloud API: nas demais a engine manda texto livre e
  # o campo é ignorado. A tela precisa saber disso para não oferecer o que não vale.
  def editavel?(hook)
    catalogo_de(hook).disponivel?
  end

  def configuracao_do_override(bruto)
    bruto.reject { |chave, _valor| chave.to_s.match?(METADADO) }
  end

  def agente_payload(bot, hook)
    { id: bot.id, nome: bot.name, elegivel: agente_elegivel?(bot, hook) }
  end

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
    locale = resolve.call('whatsapp_template_locale')
    {
      template: template,
      template_locale: locale,
      template_sincronizado: template_sincronizado?(hook, template, locale),
      template_campos: resolve.call('whatsapp_template_body_fields'),
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

  # O template configurado está entre os APROVADOS que o canal sincronizou, no idioma
  # configurado? Quando não está, a abertura simplesmente não sai — e hoje isso só aparece
  # no log. Nome e idioma juntos porque a Meta trata o par como templates diferentes, e é
  # assim que o envio procura (`Whatsapp::TemplateProcessorService#find_template`).
  # `nil` = o canal não expõe templates, então não dá para afirmar nada.
  def template_sincronizado?(hook, nome, locale)
    return nil if nome.blank?

    catalogo = catalogo_de(hook)
    return nil unless catalogo.disponivel?

    catalogo.encontrar(nome, locale.presence || DEFAULT_LOCALE).present?
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
      allowlist: allowlist(hook),
      opcoes: opcoes_de(hook)
    }
  end
end
