# frozen_string_literal: true

# Bloco 4.18 — o relatorio que responde **"quantos leads perdemos e onde"**.
#
# "Quantos" e a contagem de abandonos; "onde" e a distribuicao por ETAPA em que a pessoa
# parou (o dropout por etapa da medicao M13). Sem a etapa o numero nao serve para nada:
# saber que 60% desistem nao diz o que consertar; saber que 45% desistem no campo de CNPJ
# diz.
#
# A conta e feita no BANCO (group + count), nao em Ruby: a tabela cresce com o trafego do
# site do cliente, e carregar tudo para contar em memoria seria o mesmo defeito que a
# tabela existe para evitar.
class Widget::PartialLeads::Report
  def initialize(account:, since: nil, until_time: nil, inbox: nil)
    @account = account
    @since = since
    @until_time = until_time
    @inbox = inbox
  end

  # {
  #   started:    quantos comecaram a responder na janela
  #   completed:  quantos concluiram o pre-chat (viraram conversa)
  #   abandoned:  quantos ficaram pelo caminho
  #   completion_rate: concluidos / iniciados, 0.0 quando nao houve ninguem
  #   by_step:    { etapa => quantos pararam ali }  <- o "ONDE"
  #   by_step_name: { nome_do_campo => quantos }    <- o "ONDE" em lingua de gente
  # }
  def perform
    started = scope.count
    completed = scope.where.not(completed_at: nil).count
    abandoned = started - completed

    {
      started: started,
      completed: completed,
      abandoned: abandoned,
      completion_rate: started.zero? ? 0.0 : (completed.to_f / started).round(4),
      by_step: abandoned_scope.group(:step_reached).count.transform_keys(&:to_i).sort.to_h,
      by_step_name: abandoned_scope.where.not(step_key: nil).group(:step_key).count
    }
  end

  private

  def scope
    relation = WidgetPartialLead.where(account_id: @account.id)
    relation = relation.where(inbox_id: @inbox.id) if @inbox.present?
    relation = relation.where(last_answered_at: @since..) if @since.present?
    relation = relation.where(last_answered_at: ..@until_time) if @until_time.present?
    relation
  end

  # "Perdemos" e quem NAO concluiu — inclusive quem ainda nao passou pela janela de
  # abandono. Contar so `abandoned_at` preenchido subestimaria o prejuizo justamente na
  # janela mais recente, que e a que o cliente olha.
  def abandoned_scope
    scope.where(completed_at: nil)
  end
end
