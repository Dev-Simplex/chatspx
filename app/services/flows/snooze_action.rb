# frozen_string_literal: true

# Adia (snooze) a conversa com uma DURAÇÃO opcional. Misturado no Flows::ActionService,
# sobrepõe o base ActionService#snooze_conversation — que ignora params e faz só `snoozed!`
# (snooze INDEFINIDO). Depende do host: @conversation.
#
# NÃO inventamos scheduler nem coluna: reusa o MESMO caminho da UI de snooze. Snooze "até X" no
# Chatwoot é `status=:snoozed` + a coluna `snoozed_until` gravados no MESMO save (é o que o
# Conversations::ToggleStatusService#set_conversation_status faz). O before_save
# :ensure_snooze_until_reset da Conversation preserva o snoozed_until (só o zera quando o status
# resultante NÃO é snoozed). O REOPEN é do próprio produto: o TriggerScheduledItemsJob
# (config/schedule.yml, a cada 5 min) dispara o Conversations::ReopenSnoozedConversationsJob, que
# reabre toda conversa snoozed cujo snoozed_until já venceu.
#
# Formato do param (OPCIONAL): action_params = [{ value: N, unit: 'minutes'|'hours'|'days'|'weeks' }].
# Atalho: um número puro é tratado como minutos ([120] == 120 min). unit ausente/desconhecida →
# 'minutes'; value ausente/≤ 0 (ou action_params vazio/nil) → snooze INDEFINIDO (comportamento atual).
module Flows::SnoozeAction
  # Unidades aceitas: whitelist fechada porque a unidade vira uma chamada de método na Integer
  # (value.public_send(unit) → ActiveSupport::Duration).
  SNOOZE_UNITS = %w[minutes hours days weeks].freeze

  private

  def snooze_conversation(action_params = nil)
    duration = snooze_duration(action_params)
    # Sem duração → snooze indefinido pelo mesmo bang do enum da base (snoozed_until fica nil e o
    # job de reopen nunca o varre — seu filtro snoozed_until: 3.days.ago..Time.current ignora nil).
    return @conversation.snoozed! if duration.nil?

    @conversation.update!(status: :snoozed, snoozed_until: Time.current + duration)
  end

  # Traduz o param opcional numa ActiveSupport::Duration — ou nil, que sinaliza snooze indefinido.
  # action_params chega como array (padrão do vocabulário de ações); o 1º elemento é a config.
  def snooze_duration(action_params)
    config = Array(action_params).first
    return if config.blank?
    return config.to_i.minutes unless config.respond_to?(:to_h) # atalho: número puro = minutos

    config = config.to_h.with_indifferent_access
    value = config[:value].to_i
    return unless value.positive?

    unit = config[:unit].to_s
    unit = 'minutes' unless SNOOZE_UNITS.include?(unit)
    value.public_send(unit)
  end
end
