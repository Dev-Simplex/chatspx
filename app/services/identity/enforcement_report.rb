# frozen_string_literal: true

# Bloco 4.15 — a lista que o estado `observado` existe para produzir: quais identificacoes
# desta inbox foram aceitas SEM assinatura verificada, ou seja, exatamente o universo que
# o estado `obrigatorio` passaria a recusar.
#
# A lista e DERIVADA de `contact_inboxes.hmac_verified`, nao de log. Log rotaciona, se
# perde e nao se conta; a coluna esta no banco e responde a mesma pergunta com o mesmo
# numero toda vez que alguem perguntar.
#
# Duas regras aqui existem para o relatorio nao mentir — as mesmas do Tracking::OriginReport:
#
#   1. Sessao anonima NAO entra. Ela nao tem identidade para verificar, e contar
#      visitante anonimo como "identificacao nao verificada" infla o numero que decide a
#      virada para estrito. So entra contact_inbox cujo contato tem email, telefone ou
#      identifier.
#   2. O que aconteceu ANTES de a observacao comecar sai em `before_observation`, nunca
#      somado ao medido e nunca zerado. Zero seria lido como "nao houve nada", e isso e
#      mentira: houve trafego, so nao havia ninguem anotando.
class Identity::EnforcementReport
  MAX_ROWS = 50

  def initialize(inbox:)
    @inbox = inbox
  end

  def perform
    {
      inbox_id: @inbox.id,
      state: @inbox.resolved_identity_enforcement,
      observed_since: observed_since,
      unverified: {
        total: unverified_scope.count,
        since_observation: since_observation_count,
        before_observation: before_observation_count,
        covers_whole_history: observed_since.blank?
      },
      rows: rows
    }
  end

  private

  # Uma identificacao nao verificada e uma sessao que ficou amarrada a uma identidade sem
  # que a assinatura tenha sido conferida. Sem identidade nao ha o que verificar.
  def unverified_scope
    @inbox.contact_inboxes
          .where(hmac_verified: false)
          .joins(:contact)
          .where(
            "COALESCE(contacts.email, '') <> '' OR COALESCE(contacts.phone_number, '') <> '' " \
            "OR COALESCE(contacts.identifier, '') <> ''"
          )
  end

  def observed_since
    @observed_since ||= @inbox.identity_enforcement_observed_since_time
  end

  # `nil` e nao `0`: sem marca de inicio nao se mediu nada, e nao se sabe quanto do
  # historico e recente. Zero afirmaria que nao houve nenhuma.
  def since_observation_count
    return if observed_since.blank?

    unverified_scope.where(contact_inboxes: { updated_at: observed_since.. }).count
  end

  def before_observation_count
    return if observed_since.blank?

    unverified_scope.where(contact_inboxes: { updated_at: ...observed_since }).count
  end

  def rows
    unverified_scope
      .includes(:contact)
      .order(updated_at: :desc)
      .limit(MAX_ROWS)
      .map { |contact_inbox| row_for(contact_inbox) }
  end

  def row_for(contact_inbox)
    contact = contact_inbox.contact
    {
      contact_inbox_id: contact_inbox.id,
      contact_id: contact.id,
      identity_fields: %i[email phone_number identifier].select { |field| contact.public_send(field).present? },
      updated_at: contact_inbox.updated_at
    }
  end
end
