# Escreve o override de roteamento de UMA campanha: template da abertura, campos que
# preenchem as variáveis dele, agente e time.
#
# O ponto deste serviço é a RECUSA, não a gravação. Override é a configuração mais fácil de
# quebrar em silêncio do produto: o par (template, campos) que não bate faz a Meta responder
# #132000, a abertura não sai, o lead entra mudo e ninguém percebe até alguém garimpar log.
# Por isso ele não confia no que chega — resolve o template no canal, conta as variáveis do
# template APROVADO e valida a configuração RESULTANTE (override + padrão do hook), que é o
# que a engine vai de fato usar. Se o resultado não fecha, nada é gravado.
#
# Agnóstico: não conhece cliente, campanha nem nome de template. Multi-tenant: opera no hook
# de captação da própria conta, e uma conta sem hook simplesmente não tem o que editar.
class LeadCampaigns::RoutingUpdater
  # As chaves de settings que esta tela governa. O resto do override (lead_tipo, template de
  # catálogo, empreendimento) continua sendo configurado fora daqui e é preservado intacto.
  CHAVES = %w[whatsapp_template_name whatsapp_template_locale whatsapp_template_body_fields
              assign_agent_bot_id assign_team_id].freeze
  SEM_VARIAVEL = Meta::LeadAds::CreateConversationService::NO_BODY_FIELDS
  CAMPOS_VALIDOS = Meta::LeadAds::CreateConversationService::BODY_FIELDS
  DEFAULT_LOCALE = LeadCampaigns::ConfigResolver::DEFAULT_LOCALE

  attr_reader :erros

  # `params` chega da tela: :template, :template_locale, :campos (Array), :agente, :time.
  # Valor em branco significa "voltar ao padrão do hook" — apagar a chave do override, não
  # gravar vazio (gravar vazio esconderia o padrão e a tela mentiria sobre a herança).
  def initialize(account:, campaign_id:, params:, user: nil)
    @account = account
    @campaign_id = campaign_id.to_s.strip
    @params = params || {}
    @user = user
    @erros = []
  end

  def perform
    return false unless alvo_valido?

    override = override_resultante
    return false if @erros.any?

    validar_configuracao_efetiva(override)
    return false if @erros.any?

    gravar(override)
    true
  end

  private

  def resolver
    @resolver ||= LeadCampaigns::ConfigResolver.new(@account)
  end

  def hook
    @hook ||= resolver.hook_de(@campaign_id)
  end

  def catalogo
    @catalogo ||= resolver.catalogo_de(hook)
  end

  def alvo_valido?
    return erro(:campanha, 'campanha_sem_id') if @campaign_id.blank?
    return erro(:campanha, 'campanha_sem_hook') if hook.nil?

    true
  end

  # ------------------------------------------------------------------ montagem

  # O override que vai para o banco: o que já existia, menos as chaves desta tela, mais as
  # que o formulário mandou preencher. Assim uma chave em branco some de verdade e a
  # campanha volta a herdar do hook.
  def override_resultante
    atual = todos_os_overrides[@campaign_id]
    base = atual.is_a?(Hash) ? atual.except(*CHAVES) : {}
    base.merge(mudancas)
  end

  def configuracoes
    hook.settings || {}
  end

  def todos_os_overrides
    valor = configuracoes['campaign_overrides']
    valor.is_a?(Hash) ? valor : {}
  end

  def mudancas
    {}.merge(mudanca_de_template).merge(mudanca_de_atendimento)
  end

  def mudanca_de_template
    nome = @params[:template].to_s.strip
    return {} if nome.blank?

    descritor = descritor_escolhido(nome)
    return {} if descritor.nil?

    campos = campos_para(descritor)
    return {} if campos.nil?

    { 'whatsapp_template_name' => descritor[:nome],
      'whatsapp_template_locale' => descritor[:idioma].presence || DEFAULT_LOCALE,
      'whatsapp_template_body_fields' => campos }
  end

  # O idioma NÃO é digitado: vem do template escolhido, porque a Meta casa o template pelo
  # par (nome, idioma) e um idioma diferente do aprovado derruba o envio do mesmo jeito.
  def descritor_escolhido(nome)
    return erro_nil(:template, 'template_sem_canal') unless catalogo.disponivel?

    descritor = catalogo.encontrar(nome, @params[:template_locale])
    if descritor.nil?
      return erro_nil(:template, 'template_ambiguo', template: nome) if catalogo.ambiguo?(nome)

      return erro_nil(:template, 'template_nao_aprovado', template: nome)
    end
    return erro_nil(:template, "template_#{descritor[:impedimento]}", template: nome) if descritor[:impedimento]

    descritor
  end

  # O CORAÇÃO: a quantidade de campos é DERIVADA do template aprovado, nunca digitada. Sobra
  # ou falta campo e a Meta recusa a mensagem inteira com #132000.
  def campos_para(descritor)
    esperadas = descritor[:variaveis].size
    campos = Array(@params[:campos]).map { |campo| campo.to_s.strip }.reject(&:blank?)
    return SEM_VARIAVEL if esperadas.zero?

    invalidos = campos - CAMPOS_VALIDOS
    return erro_nil(:campos, 'campos_invalidos', campos: invalidos.join(', ')) if invalidos.any?
    return erro_nil(:campos, 'campos_quantidade', esperadas: esperadas, recebidos: campos.size) if campos.size != esperadas

    campos.join(',')
  end

  def mudanca_de_atendimento
    { 'assign_agent_bot_id' => agente, 'assign_team_id' => time }.compact
  end

  def agente
    id = @params[:agente].to_s.strip
    return nil if id.blank?

    bot = AgentBot.accessible_to(@account).find_by(id: id)
    return erro_nil(:agente, 'agente_inexistente') if bot.nil?
    return erro_nil(:agente, 'agente_nao_elegivel', agente: bot.name) unless resolver.agente_elegivel?(bot, hook)

    bot.id.to_s
  end

  def time
    id = @params[:time].to_s.strip
    return nil if id.blank?

    equipe = @account.teams.find_by(id: id)
    return erro_nil(:time, 'time_inexistente') if equipe.nil?

    equipe.id.to_s
  end

  # -------------------------------------------------------------- configuração

  # Valida o que a engine VAI usar, não o que o formulário mandou: o override herda do hook
  # tudo que não declara. Sem isso, limpar o template do override deixaria a campanha caindo
  # num padrão quebrado — e a tela diria que está tudo certo.
  def validar_configuracao_efetiva(override)
    return unless catalogo.disponivel?

    nome = efetivo(override, 'whatsapp_template_name')
    return erro(:template, 'template_ausente') if nome.blank?

    descritor = catalogo.encontrar(nome, efetivo(override, 'whatsapp_template_locale').presence || DEFAULT_LOCALE)
    return erro(:template, 'template_efetivo_invalido', template: nome) if descritor.nil?
    return erro(:template, "template_#{descritor[:impedimento]}", template: nome) if descritor[:impedimento]

    validar_campos_efetivos(descritor, efetivo(override, 'whatsapp_template_body_fields'))
  end

  # Espelha `Meta::LeadAds::CreateConversationService#template_body_params`, inclusive o
  # default: campo em branco NÃO significa "template sem variável", significa `first_name` —
  # a armadilha que este serviço existe para fechar.
  def validar_campos_efetivos(descritor, configurado)
    esperadas = descritor[:variaveis].size
    enviados = if configurado.to_s.strip.casecmp?(SEM_VARIAVEL)
                 0
               else
                 (configurado.to_s.strip.presence || CAMPOS_VALIDOS.first).split(',').count { |campo| campo.strip.present? }
               end
    return if enviados == esperadas

    erro(:campos, 'campos_quantidade_efetiva', template: descritor[:nome], esperadas: esperadas, recebidos: enviados)
  end

  def efetivo(override, chave)
    override[chave].to_s.strip.presence || configuracoes[chave].to_s.strip.presence
  end

  # ------------------------------------------------------------------ gravação

  def gravar(override)
    overrides = todos_os_overrides.deep_dup
    anterior = overrides[@campaign_id].is_a?(Hash) ? overrides[@campaign_id] : {}
    if configuracao(override).empty?
      overrides.delete(@campaign_id)
    else
      overrides[@campaign_id] = override.merge(autoria)
    end

    ActiveRecord::Base.transaction do
      hook.update!(settings: configuracoes.merge('campaign_overrides' => overrides))
      registrar(anterior, overrides[@campaign_id] || {})
    end
  end

  # Override que ficou só com autoria não é override: apagar a entrada é o que devolve a
  # campanha para o padrão do hook, na engine e na tela.
  def configuracao(override)
    override.reject { |chave, _valor| chave.to_s.match?(LeadCampaigns::ConfigResolver::METADADO) }
  end

  # Rastro visível onde a mudança acontece. A tabela de auditoria é o registro forense, mas
  # ela é Enterprise e vive atrás de um feature flag — a maioria das contas não a enxerga.
  # Estas duas chaves a tela sempre mostra.
  def autoria
    { '_atualizado_por' => @user&.available_name.to_s.presence,
      '_atualizado_em' => Time.current.iso8601 }.compact
  end

  # Registro forense do que mudou. Grava SÓ as chaves de roteamento: o resto de
  # `settings` são credenciais do hook (app_secret, page_access_token) e não entra em
  # auditoria nenhuma. Dentro da transação de propósito — escrita sem rastro é o problema
  # que esta fatia veio resolver, então uma auditoria que falha desfaz a gravação.
  def registrar(antes, depois)
    Audited.audit_class.create!(
      auditable_type: 'Integrations::Hook', auditable_id: hook.id,
      associated_type: 'Account', associated_id: @account.id,
      action: 'update', user: @user,
      comment: "lead_campaigns.roteamento campanha=#{@campaign_id}",
      audited_changes: { 'campaign_overrides' => { @campaign_id => { 'de' => configuracao(antes), 'para' => configuracao(depois) } } }
    )
  end

  # ------------------------------------------------------------------ erros

  def erro(campo, codigo, **dados)
    @erros << { campo: campo, mensagem: I18n.t("lead_campaigns.errors.#{codigo}", **dados) }
    false
  end

  def erro_nil(campo, codigo, **dados)
    erro(campo, codigo, **dados)
    nil
  end
end
