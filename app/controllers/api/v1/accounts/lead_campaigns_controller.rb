# Tela de campanhas de captação (fatia 1 — SÓ LEITURA).
#
# Responde a duas perguntas que hoje só se responde com SQL: *quais campanhas trouxeram
# lead no período* e *como cada uma está configurada*. Não escreve nada, não fala com a
# API de Ads da Meta e não conhece campanha que nunca gerou lead — tudo o que aparece
# aqui já existe no banco:
#
#   - o carimbo de origem na conversa (`custom_attributes.meta_campanha` e irmãos), que a
#     engine de captação grava em `stamp_campaign_visibility`;
#   - o template que DE FATO saiu, em `messages.additional_attributes.template_params.name`
#     (não em `content_attributes`, onde ele não está);
#   - a configuração viva do hook de captação (`Integrations::Hook#settings`), incluindo os
#     overrides por campanha que o `Meta::LeadAds::CreateConversationService#hook_setting`
#     resolve em runtime.
#
# Mostrar *configurado* e *enviado* lado a lado é o ponto da tela: quando divergem, ou o
# override entrou depois dos leads, ou o template configurado não existe mais no canal.
#
# AGNÓSTICO: nenhum nome de cliente, campanha ou template no código. Conta sem hook de
# captação recebe `habilitado: false` e não vê a tela.
#
# PERMISSÃO: volume por campanha todo mundo vê; **configuração de roteamento (template,
# agente, time, override, hooks) é só para admin**.
#
# Read-only e defensivo: seção que falhar volta vazia em vez de derrubar a tela.
class Api::V1::Accounts::LeadCampaignsController < Api::V1::Accounts::BaseController
  before_action :current_account

  # Apps de captação de lead por formulário. Todos entregam pela mesma engine
  # (`Meta::LeadAds::CreateConversationService`) e por isso compartilham o formato de
  # settings — inclusive `campaign_overrides`.
  INTAKE_APP_IDS = %w[meta_lead_ads site_leads].freeze

  # App cujos leads carregam id de campanha (anúncio). Os demais (formulário de site)
  # entregam lead sem campanha nenhuma — é o que separa um hook do outro quando a conta
  # tem mais de um.
  CAMPAIGN_APP_ID = 'meta_lead_ads'.freeze

  # Marcador que a engine grava em `conversation.additional_attributes['source']`, para
  # qualquer origem de formulário. É o recorte do "lead de formulário" no banco.
  INTAKE_SOURCE = 'meta_lead_ads'.freeze

  DEFAULT_PERIOD_DAYS = 30
  # Teto do período: a consulta varre as conversas do intervalo linha a linha.
  MAX_PERIOD_DAYS = 366
  MAX_ROWS = 100

  # Nome da campanha como o time o vê no painel, com o registro do lead como reserva
  # para a conversa cujo carimbo não chegou a rodar.
  NOME_SQL = Arel.sql(
    "COALESCE(NULLIF(conversations.custom_attributes->>'meta_campanha', ''), " \
    "conversations.additional_attributes->'lead'->>'campaign_name')"
  ).freeze
  TIPO_SQL = Arel.sql("conversations.custom_attributes->>'meta_tipo'").freeze
  ORIGEM_SQL = Arel.sql("conversations.custom_attributes->>'meta_origem'").freeze
  TEMPLATE_NOME_SQL = Arel.sql("messages.additional_attributes->'template_params'->>'name'").freeze

  def show
    return render json: { habilitado: false, admin: admin?, campanhas: [], hooks: [] } if intake_hooks.empty?

    render json: {
      habilitado: true,
      admin: admin?,
      periodo: { de: periodo.first, ate: periodo.last },
      hooks: admin? ? hooks_payload : [],
      campanhas: campanhas,
      totais: totais
    }
  end

  private

  def admin?
    Current.account_user&.administrator?
  end

  # Hook desabilitado continua listado: ele não roteia mais nada, mas é a configuração
  # dele que explica os leads que já entraram no período.
  def intake_hooks
    @intake_hooks ||= Current.account.hooks.where(app_id: INTAKE_APP_IDS).order(:id).to_a
  end

  # ------------------------------------------------------------------ período

  def periodo
    @periodo ||= begin
      ate = parse_time(params[:ate]) || Time.zone.now.end_of_day
      de = parse_time(params[:de]) || (ate - DEFAULT_PERIOD_DAYS.days).beginning_of_day
      de = ate - MAX_PERIOD_DAYS.days if de > ate || (ate - de) > MAX_PERIOD_DAYS.days
      [de, ate]
    end
  end

  def parse_time(valor)
    valor.present? ? Time.zone.parse(valor.to_s) : nil
  rescue ArgumentError, TypeError
    nil
  end

  # ------------------------------------------------------------------ leitura

  def conversas
    @conversas ||= Current.account.conversations
                          .where(created_at: periodo.first..periodo.last)
                          .where("conversations.additional_attributes->>'source' = ?", INTAKE_SOURCE)
  end

  # Uma linha por conversa criada no período: [id, contact_id, campanha, tipo, origem].
  # Conversa reusada (o contato já tinha uma) fica de fora por definição — a unidade aqui
  # é "lead que abriu conversa no período", e é isso que a tela diz no subtítulo.
  def linhas
    @linhas ||= conversas.pluck(:id, :contact_id, NOME_SQL, TIPO_SQL, ORIGEM_SQL)
  rescue StandardError
    []
  end

  # Nome da campanha → id. O par (id, nome) é gravado JUNTO no contato, no momento em que
  # ele nasce; continua sendo um par válido mesmo depois que outra campanha reusa aquele
  # contato. Por isso ele serve de DICIONÁRIO nome→id, e nunca de atribuição por conversa
  # (o contato guarda a campanha da PRIMEIRA entrada, não a desta conversa).
  def dicionario_ids
    @dicionario_ids ||= begin
      pares = Contact.where(account_id: Current.account.id, id: linhas.map { |linha| linha[1] }.compact.uniq)
                     .pluck(Arel.sql("contacts.additional_attributes->>'campaign_id'"),
                            Arel.sql("contacts.additional_attributes->>'campaign_name'"))
      contagem = Hash.new { |hash, chave| hash[chave] = Hash.new(0) }
      pares.each { |id, nome| contagem[nome][id] += 1 if id.present? && nome.present? }
      contagem
    end
  rescue StandardError
    {}
  end

  # Template do PRIMEIRO disparo de cada conversa — o opener. Vale a primeira mensagem com
  # `template_params` porque a conversa nasceu no período: follow-up e reativação vêm depois.
  def template_por_conversa
    @template_por_conversa ||= begin
      escopo = Message.where(account_id: Current.account.id, conversation_id: conversas.select(:id))
                      .where("messages.additional_attributes->'template_params'->>'name' IS NOT NULL")
      # `reorder(nil)`: o default_scope de Message ordena por created_at, e o ORDER BY
      # sobrevive ao GROUP BY e quebra a agregação no Postgres.
      primeiras = escopo.reorder(nil).group(:conversation_id).minimum(:id)
      Message.where(id: primeiras.values).pluck(:conversation_id, TEMPLATE_NOME_SQL).to_h
    end
  rescue StandardError
    {}
  end

  # ------------------------------------------------------------------ linhas

  def campanhas
    observadas = linhas.group_by { |linha| linha[2].to_s.strip.presence }
    ordenadas = observadas.sort_by { |_nome, registros| -registros.size }
    linhas_observadas = ordenadas.first(MAX_ROWS).map { |nome, registros| linha_observada(nome, registros) }
    (linhas_observadas + linhas_so_configuradas(observadas.keys)).first(MAX_ROWS)
  end

  def linha_observada(nome, registros)
    campaign_id, ambiguo = resolve_id(nome)
    linha = {
      nome: nome,
      campaign_id: campaign_id,
      id_ambiguo: ambiguo,
      leads: registros.size,
      tipos: contar(registros) { |linha_crua| linha_crua[3] },
      origens: contar(registros) { |linha_crua| linha_crua[4] },
      templates_enviados: templates_enviados(registros)
    }
    admin? ? linha.merge(configuracao(campaign_id)) : linha
  end

  # Campanha configurada no hook que não trouxe lead no período entra com zero: a pergunta
  # "como esta campanha está configurada" continua valendo quando o volume é zero.
  def linhas_so_configuradas(nomes_observados)
    return [] unless admin?

    ids_observados = nomes_observados.filter_map { |nome| resolve_id(nome).first }
    intake_hooks.flat_map { |hook| overrides(hook).keys }.uniq
                .reject { |id| ids_observados.include?(id) }
                .map { |id| linha_sem_lead(id) }
  end

  def linha_sem_lead(campaign_id)
    {
      nome: nil, campaign_id: campaign_id, id_ambiguo: false, leads: 0,
      tipos: {}, origens: {}, templates_enviados: []
    }.merge(configuracao(campaign_id))
  end

  # Nome com mais de um id no dicionário acontece quando a campanha é renomeada na Meta.
  # Vale o id mais frequente, e a linha diz que houve ambiguidade em vez de escondê-la.
  def resolve_id(nome)
    ids = dicionario_ids[nome]
    return [nil, false] if ids.blank?

    [ids.max_by { |_id, total| total }.first, ids.size > 1]
  end

  def templates_enviados(registros)
    mapa = template_por_conversa
    contagem = contar(registros) { |linha_crua| mapa[linha_crua[0]] }
    contagem.sort_by { |_nome, total| -total }.map { |nome, total| { nome: nome, leads: total } }
  end

  # Conta ocorrências ignorando o que veio vazio — dado sujo da origem não vira categoria.
  def contar(registros)
    registros.each_with_object(Hash.new(0)) do |registro, acc|
      chave = yield(registro).to_s.strip
      acc[chave] += 1 if chave.present?
    end
  end

  # ------------------------------------------------------- configuração (admin)

  # Espelha o `hook_setting` da engine: o valor do override quando presente, senão o
  # global do hook. `sobrescritos` diz quais campos vieram do override, para a tela poder
  # marcar exatamente o que foi customizado.
  def configuracao(campaign_id)
    hook = hook_para(campaign_id)
    return { hook_id: nil, origem: 'indefinido', sobrescritos: [] } if hook.nil?

    override = overrides(hook)[campaign_id.to_s] || {}
    settings = hook.settings || {}
    resolve = ->(chave) { override[chave].to_s.strip.presence || settings[chave].to_s.strip.presence }
    template = resolve.call('whatsapp_template_name')

    {
      hook_id: hook.id,
      origem: override.present? ? 'override' : 'padrao',
      sobrescritos: override.keys.sort,
      template: template,
      template_sincronizado: template_sincronizado?(hook, template),
      template_imovel: resolve.call('imovel_template_name'),
      lead_tipo: resolve.call('lead_tipo'),
      agente: agent_bots[resolve.call('assign_agent_bot_id').to_i],
      time: times[resolve.call('assign_team_id').to_i],
      bloqueada: bloqueada?(hook, campaign_id)
    }
  end

  # Qual hook responde por esta campanha. Determinístico, e sem chutar quando a conta tem
  # mais de um hook do mesmo tipo:
  #   1. o hook que tem override para o id;
  #   2. o hook cujo allowlist inclui o id;
  #   3. campanha COM id → o único hook de campanha da conta;
  #      campanha SEM id → o único hook de captação sem campanha (ex.: formulário de site);
  #   4. nada resolveu → indefinido (a tela mostra o volume e omite a configuração).
  def hook_para(campaign_id)
    id = campaign_id.to_s
    if id.present?
      com_override = intake_hooks.find { |hook| overrides(hook).key?(id) }
      return com_override if com_override

      com_allowlist = intake_hooks.select { |hook| allowlist(hook).include?(id) }
      return com_allowlist.first if com_allowlist.size == 1
    end

    candidatos = intake_hooks.select { |hook| (hook.app_id == CAMPAIGN_APP_ID) == id.present? }
    candidatos.size == 1 ? candidatos.first : nil
  end

  def overrides(hook)
    valor = (hook.settings || {})['campaign_overrides']
    valor.is_a?(Hash) ? valor.select { |_id, config| config.is_a?(Hash) } : {}
  end

  def allowlist(hook)
    bruto = (hook.settings || {})['allowed_campaign_ids']
    lista = bruto.is_a?(Array) ? bruto : bruto.to_s.split(',')
    lista.map { |id| id.to_s.strip }.reject(&:blank?)
  end

  # Allowlist não-vazia que não inclui a campanha = lead ignorado na entrada. É config, e
  # explica sozinha uma campanha com zero lead.
  def bloqueada?(hook, campaign_id)
    lista = allowlist(hook)
    return false if lista.empty? || campaign_id.blank?

    !lista.include?(campaign_id.to_s)
  end

  # O template configurado existe entre os aprovados que o canal já sincronizou? Quando não,
  # a abertura não sai — e hoje isso só aparece no log.
  def template_sincronizado?(hook, nome)
    return nil if nome.blank?

    aprovados = templates_do_canal(hook)
    return nil if aprovados.nil?

    aprovados.include?(nome)
  end

  def templates_do_canal(hook)
    @templates_do_canal ||= {}
    return @templates_do_canal[hook.id] if @templates_do_canal.key?(hook.id)

    canal = Inbox.find_by(account_id: Current.account.id, id: (hook.settings || {})['target_inbox_id'])&.channel
    lista = canal.respond_to?(:message_templates) ? canal.message_templates : nil
    @templates_do_canal[hook.id] = lista.is_a?(Array) ? lista.filter_map { |t| t['name'] if t.is_a?(Hash) } : nil
  rescue StandardError
    @templates_do_canal[hook.id] = nil
  end

  def agent_bots
    @agent_bots ||= AgentBot.where(id: ids_configurados('assign_agent_bot_id'))
                            .pluck(:id, :name).to_h { |id, nome| [id, { id: id, nome: nome }] }
  rescue StandardError
    {}
  end

  def times
    @times ||= Current.account.teams.where(id: ids_configurados('assign_team_id'))
                      .pluck(:id, :name).to_h { |id, nome| [id, { id: id, nome: nome }] }
  rescue StandardError
    {}
  end

  # Todos os ids daquela chave que aparecem no hook ou em qualquer override dele, para
  # resolver nome de agente e time numa consulta só.
  def ids_configurados(chave)
    intake_hooks.flat_map do |hook|
      settings = hook.settings || {}
      [settings[chave]] + overrides(hook).values.map { |config| config[chave] }
    end.filter_map { |id| id.presence&.to_i }.uniq
  end

  # ------------------------------------------------------------------ resumo

  def hooks_payload
    intake_hooks.map do |hook|
      settings = hook.settings || {}
      {
        id: hook.id,
        app_id: hook.app_id,
        habilitado: hook.enabled?,
        pagina: settings['page_name'].presence || settings['site_name'].presence,
        inbox: Inbox.find_by(account_id: Current.account.id, id: settings['target_inbox_id'])&.slice(:id, :name),
        template: settings['whatsapp_template_name'].presence,
        agente: agent_bots[settings['assign_agent_bot_id'].to_i],
        time: times[settings['assign_team_id'].to_i],
        campanhas_com_override: overrides(hook).keys.size,
        allowlist: allowlist(hook)
      }
    end
  rescue StandardError
    []
  end

  def totais
    { leads: linhas.size, campanhas: linhas.group_by { |linha| linha[2] }.size }
  end
end
