# frozen_string_literal: true

# Avisos automáticos na sala de um time (opt-in por evento, desligados por padrão), guardados em
# internal_channels.settings['auto_alerts']:
#   lead_parado — lead que o rodízio designou e ninguém pegou além do limite. A regra é a do cartão
#                 "Sem movimento" da tela Rodízio (Spx::Distribuicao::ContabilizacaoService#sem_movimento),
#                 com o mesmo recorte por time: a conversa do lead está no time da sala.
#   meta_batida — alguém do time atingiu a meta do mês num indicador (PerformanceGoals::RankingService).
#
# Cada aviso leva suas chaves em content_attributes['alert']['keys'] e só posta o que a sala ainda não tem:
# um aviso por lead e ciclo de designação; na meta, uma chave por pessoa, indicador e mês, mas as metas que a
# mesma pessoa bate de uma vez saem num aviso só. Avisos antigos guardam uma única chave em ['alert']['key'].
class InternalChannels::AutoAlertsService
  EVENTS = %w[lead_parado meta_batida].freeze
  ICONS = { 'lead_parado' => 'i-lucide-alarm-clock', 'meta_batida' => 'i-lucide-trophy' }.freeze

  def self.enabled?(channel, event)
    channel.settings.dig('auto_alerts', event) == true
  end

  # Admin da conta muda em qualquer sala de time; quem supervisiona times específicos, só nas dos seus.
  def self.can_manage?(channel, account_user)
    return false unless channel.team? && account_user&.administrator?

    supervised = account_user.user.supervised_team_ids_for(channel.account_id)
    supervised.empty? || supervised.include?(channel.team_id)
  end

  def initialize(channel)
    @channel = channel
    @account = channel.account
  end

  def perform
    I18n.with_locale(@account.locale || I18n.default_locale) do
      lead_parado if self.class.enabled?(@channel, 'lead_parado')
      meta_batida if self.class.enabled?(@channel, 'meta_batida')
    end
  end

  private

  def lead_parado
    leads = Spx::Distribuicao::ContabilizacaoService.new(account: @account, team_id: @channel.team_id).sem_movimento[:leads]
    leads.each do |lead|
      text = I18n.t('internal_chat_alerts.lead_parado',
                    duration: duration(lead[:minutos_parado]), consultor: lead[:corretor],
                    contato: lead[:contato], id: lead[:display_id])
      post("lead_parado:#{lead[:conversation_id]}:#{lead[:designado_em].to_i}", text, lead[:conversation_id])
    end
  end

  def meta_batida
    month = PerformanceGoals::Month.current(@account)
    rows = PerformanceGoals::RankingService.new(account: @account, month: month, scope: 'users', team_id: @channel.team_id).perform[:rows]
    rows.each do |row|
      hit = row[:metrics].select { |_metric, data| data[:attainment].to_f >= 1 }
                         .to_h { |metric, data| ["meta_batida:#{row[:id]}:#{metric}:#{month.strftime('%Y-%m')}", [metric, data]] }
                         .reject { |key, _| posted?(key) }
      post(hit.keys, meta_batida_text(row[:name], hit.values)) if hit.any?
    end
  end

  # Uma frase por pessoa: "Ana bateu 2 metas do mês: 12 de 10 conversas resolvidas; NPS 80 (meta: 70)".
  def meta_batida_text(name, metrics)
    parts = metrics.map do |metric, data|
      I18n.t("internal_chat_alerts.meta_batida.#{metric}", actual: number(data[:actual]), goal: number(data[:goal]))
    end
    I18n.t('internal_chat_alerts.meta_batida.message', count: parts.size, name: name, parts: parts.join('; '))
  end

  def posted?(key)
    @channel.messages.exists?(["content_attributes -> 'alert' ->> 'key' = :key OR " \
                               "jsonb_exists(content_attributes -> 'alert' -> 'keys', :key)", { key: key }])
  end

  def post(keys, content, conversation_id = nil)
    keys = Array(keys)
    return if keys.all? { |key| posted?(key) }

    kind = keys.first.split(':').first

    message = @channel.messages.create!(
      message_type: :system, content: content, shared_conversation_id: conversation_id,
      content_attributes: { 'icon' => ICONS[kind], 'alert' => { 'kind' => kind, 'keys' => keys } }
    )
    InternalMessages::BroadcastService.created(message)
  end

  def duration(minutes)
    minutes = minutes.to_i
    return I18n.t('internal_chat_alerts.minutes', m: minutes) if minutes < 60
    return I18n.t('internal_chat_alerts.hours', h: minutes / 60, m: minutes % 60) if minutes < 1440

    I18n.t('internal_chat_alerts.days', d: minutes / 1440, h: (minutes % 1440) / 60)
  end

  def number(value)
    ActiveSupport::NumberHelper.number_to_rounded(value, precision: 1, strip_insignificant_zeros: true, locale: I18n.locale)
  end
end
