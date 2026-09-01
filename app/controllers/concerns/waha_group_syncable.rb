# frozen_string_literal: true

# Mantem a lista de integrantes de um grupo de WhatsApp (inbox WAHA) atualizada
# sem o agente precisar clicar em "Sincronizar agora".
#
# Abrir a conversa agenda o sync. A resposta NAO espera: o payload sai na hora
# com o snapshot que ja existe (ou sem nenhum, na primeira vez) e o job atualiza
# em background. Quando ele grava algo novo, `Waha::GroupSyncService` reemite a
# conversa pelo websocket e o painel se corrige sozinho na tela de quem esta com
# ela aberta.
#
# O job roda SEM `force`, entao quem decide se vale a chamada e o proprio
# `Waha::GroupSyncService`: snapshot com menos de SNAPSHOT_TTL devolve cache e
# nao encosta na WAHA. Abrir a mesma conversa dez vezes seguidas custa zero
# chamada externa.
module WahaGroupSyncable
  extend ActiveSupport::Concern

  private

  def refresh_waha_group_participants(conversation)
    return if conversation.blank? || !conversation.group?

    Waha::GroupSyncJob.perform_later(conversation.id)
  rescue StandardError => e
    # Agendar e conveniencia: falha aqui nunca pode impedir a conversa de abrir.
    Rails.logger.warn("[WAHA][GroupSync] falha ao agendar sync da conversa #{conversation&.id}: #{e.class} #{e.message}")
  end
end
