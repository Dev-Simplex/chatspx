# Bloco 3.03 — o perfil resolvido em FLAGS PLANAS.
#
# A regra que atravessa tudo (arbitragem A3): **o widget le flags planas, nunca o nome do perfil.**
# E o que impede `if (profile === 'marketing')` de se espalhar pelos arquivos do campo minado, mantem
# a matriz de teste em 16 snapshots (4 views x 2 temas x 2 viewports) em vez de 32, e mantem possivel
# o hibrido que o cliente sempre pede — marketing COM base de conhecimento.
#
# A lista das onze flags e canonica em `22-plano-widget.md` §B.3. Este arquivo e a implementacao dela;
# quem precisar acrescentar, remover ou renomear flag muda LA primeiro.
#
# Precedencia, e e o que impede o defeito silencioso: onde a flag reflete campo ja gravado, **o valor
# gravado vence o perfil, sempre**. O perfil so resolve o que nao tem valor gravado (regime 3 de A3).
class WidgetProfile
  SUPPORT = 'support'.freeze
  MARKETING = 'marketing'.freeze

  # Gatilho composto do teaser: 8 s de permanencia E 30% de scroll (plano 22 §B.4, medicao 06 §14.2 R8).
  TEASER_DELAY_MS = 8000
  TEASER_SCROLL_PERCENT = 30

  # Regime 3 de A3: campos que nascem agora e nao tem valor gravado a preservar.
  PROFILE_DEFAULTS = {
    SUPPORT => {
      'showKnowledgeBase' => true,
      'showConversationList' => true,
      'teaserEnabled' => false,
      'primaryExit' => 'none',
      'homeLayout' => 'support',
      'aiLabelPersistent' => true
    }.freeze,
    MARKETING => {
      'showKnowledgeBase' => false,
      # Em captura, a lista de conversas anteriores compete com a unica coisa que a tela quer que
      # aconteca. [INFERENCIA] — a §B.4 descreve o historico so no perfil de suporte.
      'showConversationList' => false,
      'teaserEnabled' => true,
      # 75,96% das empresas brasileiras redirecionam para o WhatsApp, e quem redireciona converte
      # +0,54 p.p. (plano 22 §B.4, do 04-players-br).
      'primaryExit' => 'whatsapp',
      'homeLayout' => 'marketing',
      'aiLabelPersistent' => true
    }.freeze
  }.freeze

  class << self
    # Aceita o canal (como o ERB chama) ou a propria inbox.
    def resolve(source)
      inbox = source.is_a?(Inbox) ? source : source.inbox
      profile = inbox.resolved_widget_profile
      defaults = PROFILE_DEFAULTS.fetch(profile, PROFILE_DEFAULTS.fetch(SUPPORT))

      defaults.merge(runtime_flags(inbox, profile))
    end

    # Regime 1 de A3: inbox NOVA. So semeia o que nasce agora e nao tem valor a preservar —
    # `widget_triggers`. Coluna ja existente (`csat_survey_enabled`, `pre_chat_form_enabled`,
    # `continuity_via_email`) NAO e semeada: o proprio aceite deste bloco exige que uma inbox com
    # `csat_survey_enabled: false` e perfil `support` continue com o CSAT desligado. O perfil PROPOE
    # a mudanca de coluna na tela (regime 2), com o administrador confirmando item a item.
    def seed_defaults(inbox)
      return unless inbox.widget_profile.present? && inbox.widget_triggers.blank?

      inbox.widget_triggers = {
        'version' => 1,
        'enabled' => inbox.widget_profile == MARKETING,
        'approach' => WidgetTriggersSchema::DEFAULT_APPROACH,
        'approach_mobile' => WidgetTriggersSchema::DEFAULT_APPROACH,
        'degrade_on_return' => WidgetTriggersSchema::DEFAULT_DEGRADE_ON_RETURN
      }
    end

    private

    # Regime 2 de A3: a flag ESPELHA o que esta gravado. Nunca o contrario.
    def runtime_flags(inbox, profile)
      channel = inbox.channel

      {
        'teaserDelayMs' => TEASER_DELAY_MS,
        'teaserScrollPercent' => TEASER_SCROLL_PERCENT,
        'captureFlow' => capture_flow(channel, profile),
        'csatOnResolve' => inbox.csat_survey_enabled?,
        'emailContinuity' => email_continuity?(channel)
      }
    end

    # A forma da captura, quando ha captura. O que decide se existe formulario e a coluna gravada
    # (`pre_chat_form_enabled`); o perfil decide apenas se ele e classico ou conversacional.
    def capture_flow(channel, profile)
      return 'form' unless channel.respond_to?(:pre_chat_form_enabled) && channel.pre_chat_form_enabled?

      profile == MARKETING ? 'conversational' : 'form'
    end

    def email_continuity?(channel)
      return false unless channel.respond_to?(:continuity_via_email)

      channel.continuity_via_email
    end
  end
end
