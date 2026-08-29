# frozen_string_literal: true

# Bloco 4.18 — a entrada do cron. O `SweepJob` trabalha POR CONTA (`perform(account_id)`),
# entao alguem precisa dizer QUAIS contas varrer; sem este job o `SweepJob` existe, e
# testado, e nunca roda — que e a mesma classe de defeito do `Flows::ResumeJob` (bloco
# 4.14): codigo escrito, comentario afirmando "roda a cada minuto" e nenhuma entrada em
# `config/schedule.yml`.
#
# O leque nao passa por `Account.find_each`: a lista sai da PROPRIA tabela, entao conta que
# nunca teve resposta parcial nao gera job nenhum. Duas consequencias, e as duas importam:
#
#   · conta que ligou a captura mas ainda nao coletou nada nao acorda um worker por minuto;
#   · conta que DESLIGOU a captura continua na lista enquanto tiver linha viva — e tem de
#     continuar, porque o expurgo de retencao (LGPD) e justamente o que apaga o que ela ja
#     coletou. Fan-out por `enabled?` deixaria esse dado guardado para sempre.
#
# O corte de `last_answered_at` e o piso das duas configuracoes: linha respondida ha menos
# de `MIN_ABANDON_MINUTES` nao pode estar abandonada sob NENHUMA configuracao (o clamp de
# `Settings` nao aceita janela menor) e nao pode estar vencida sob nenhuma retencao (o piso
# e um dia). Contas cujas linhas sao todas mais novas que isso nao tem trabalho a fazer.
class Widget::PartialLeads::SweepSchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    cutoff = Widget::PartialLeads::Settings::MIN_ABANDON_MINUTES.minutes.ago

    WidgetPartialLead.where(last_answered_at: ...cutoff)
                     .distinct
                     .pluck(:account_id)
                     .each { |account_id| Widget::PartialLeads::SweepJob.perform_later(account_id) }
  end
end
