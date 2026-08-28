# O produto passa a nascer INTEIRO ligado, em conta nova e nas que já existem.
#
# O problema que isto resolve: até aqui cada feature dependia de alguém lembrar de ligá-la conta a
# conta, e o resultado era a mesma funcionalidade existir numa máquina e não noutra. Medido em
# 28/08/2026: Catatau com 27 features ligadas, conta 3 da .229 com 36, cada uma um conjunto
# diferente. O rodízio foi o caso que expôs isso — o bloco aparecia no canvas e não rodava.
#
# NÃO É `config/features.yml` QUEM MANDA em runtime. Quem aplica o default de conta nova é
# `Featurable#enable_default_features` (before_create), lendo a linha `ACCOUNT_LEVEL_FEATURE_DEFAULTS`
# de `installation_configs`. O `ConfigLoader` semeia essa linha a partir do YAML, mas com
# `reconcile_only_new: true`: preserva o que já existe e só acrescenta chave nova. Por isso editar o
# YAML sozinho não mudaria instalação nenhuma, e esta migration mexe nos DOIS lugares.
class FeaturesPadraoDaFrota < ActiveRecord::Migration[7.1]
  # Features que ficam FORA do padrão, cada uma por um motivo verificável.
  #
  # LEGADO/DEPRECIADO — a decisão do usuário foi "liga tudo, menos o que é velho". `captain_integration`
  # é o Captain v1 (o código o marca como LEGACY_CAPTAIN_FEATURE em
  # SuperAdmin::AccountFeaturesHelper); as outras têm `deprecated: true` no próprio YAML.
  #
  # BITMASK ESTOURADO — `accounts.feature_flags` é bigint (63 bits úteis) e a POSIÇÃO no YAML define o
  # bit. Com 65 entradas, as posições 64 e 65 pedem 2^63 e 2^64: ligar qualquer uma estoura com
  # RangeError. Já documentado no fork em app/services/kanban/realtime.rb.
  #
  # INFRA/CREDENCIAL AUSENTE — medido nesta frota: `ip_lookup` exige IP_LOOKUP_API_KEY, que está vazia
  # no .env; `search_with_gin` exige um índice GIN que não existe no banco; `assignment_v2` é outro
  # motor de atribuição, com job periódico agendado, e brigaria com o rodízio;
  # `email_continuity_on_api_channel` mudaria o comportamento de e-mail das caixas Channel::Api (a
  # Sentinela tem 5).
  #
  # As demais exclusões saem de marcação do próprio YAML (`premium`, `chatwoot_internal`) e não estão
  # repetidas aqui: a regra em #features_do_padrao as filtra sozinha, para esta lista não virar uma
  # segunda fonte de verdade que sai de sincronia.
  FORA_DO_PADRAO = %w[
    captain_integration
    ip_lookup
    email_continuity_on_api_channel
    search_with_gin
    assignment_v2
    saml
    shopify_integration
    notion_integration
    linear_integration
    crm_integration
    custom_reply_email
    custom_reply_domain
    channel_voice
    help_center_embedding_search
    reply_mailer_migration
    crm_v2
    advanced_search_indexing
    disable_branding
    whatsapp_embedded_signup
  ].freeze

  def up
    nomes = features_do_padrao
    say "features do padrao: #{nomes.size}"

    atualizar_defaults(nomes)
    ligar_nas_contas_existentes(nomes)
    GlobalConfig.clear_cache
  end

  # Sem `down`: desligar features em massa é destrutivo e não é o inverso desta migration (contas que
  # já tinham a feature antes dela também perderiam). Reverter é decisão de operação, feita pela tela.
  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # A lista sai de REGRA aplicada ao YAML, não de nomes digitados: assim ela não sai de sincronia
  # quando alguém acrescentar uma feature.
  def features_do_padrao
    catalogo.reject { |f| excluir?(f) }.pluck('name')
  end

  def excluir?(feature)
    return true if feature['deprecated'] || feature['premium']
    return true if FORA_DO_PADRAO.include?(feature['name'])

    # `chatwoot_internal` sozinho NÃO basta para excluir. A marca serve para o Chatwoot esconder
    # coisas da UI do super_admin fora do cloud dele, e é usada de forma inconsistente: 3 features
    # marcadas assim vêm LIGADAS de fábrica e fazem parte do produto que rodamos
    # (`kanban_ux_v2`, `kanban_cursor_loading`, `contact_chatwoot_support_team` — o Kanban novo é o
    # caso óbvio, a Catatau usa). Excluí-las faria o padrão ficar ABAIXO do que o produto já entrega.
    # Só as internas que vêm DESLIGADAS ficam fora, porque aí são mesmo experimentais.
    feature['chatwoot_internal'] && !feature['enabled']
  end

  def catalogo
    @catalogo ||= YAML.safe_load(Rails.root.join('config/features.yml').read)
  end

  # Governa as contas NOVAS (o before_create do Featurable lê daqui).
  def atualizar_defaults(nomes)
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return say('ACCOUNT_LEVEL_FEATURE_DEFAULTS ausente, pulando') if config.blank?

    features = Array(config.value).map(&:dup)
    features.each { |f| f['enabled'] = true if nomes.include?(f['name']) }

    faltando = nomes - features.pluck('name')
    features.concat(entradas_novas(faltando))

    config.update!(value: features)
    say "defaults atualizados (#{faltando.size} chave(s) acrescentada(s))"
  end

  # Feature que existe no YAML mas ainda não tem linha no InstallationConfig (instalação antiga que
  # nunca reconciliou). Entra já ligada.
  def entradas_novas(faltando)
    return [] if faltando.empty?

    catalogo.select { |f| faltando.include?(f['name']) }
            .map { |f| f.slice('name', 'display_name').merge('enabled' => true) }
  end

  # Governa as contas que JÁ EXISTEM.
  #
  # NADA é desligado: o pedido foi "não ligue as velhas", e não "desligue as velhas". Conta que já tem
  # `captain_integration` continua com ela; a feature só deixa de entrar no padrão daqui pra frente.
  #
  # `enable_features!` usa `save` e não `save!` (Featurable), então uma validação reprovada passaria
  # CALADA. Por isso o resultado é conferido conta a conta e o que não aplicou é registrado — uma
  # migration que diz "pronto" sem ter gravado é pior que uma que falha.
  def ligar_nas_contas_existentes(nomes)
    ok = 0
    falhas = []

    Account.find_in_batches(batch_size: 100) do |contas|
      contas.each do |conta|
        conta.enable_features!(*nomes)
        faltou = nomes.reject { |n| conta.reload.feature_enabled?(n) }
        faltou.empty? ? ok += 1 : falhas << "conta #{conta.id}: #{faltou.join(', ')}"
      end
    end

    say "contas atualizadas: #{ok}"
    falhas.each { |f| say "  NAO APLICOU -> #{f}" }
  end
end
