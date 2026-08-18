# frozen_string_literal: true

# Varre os grupos das sessoes da WAHA a cada 30 min (config/schedule.yml).
#
# Antes este job chamava `get_groups` e DESCARTAVA a resposta — pagava a chamada
# so pelo efeito colateral de aquecer o mapa LID->PN dentro da WAHA. Essa resposta
# e o payload mais rico que temos: medido nesta VM, 78 grupos e 932 participantes,
# 932 deles com telefone, numa unica chamada de 240 KB. Agora ela e usada:
#
#   1. cache Redis LID -> telefone em lote (`waha:lid_pn:{session}:{lid}`), lido
#      pela ingestao de mensagem de grupo — mata o round-trip HTTP por LID;
#   2. indice grupo -> sessao, que permite descobrir em qual sessao um grupo vive
#      mesmo quando a caixa nao declara `waha_session_name`;
#   3. snapshot dos integrantes nas conversas de grupo (contrato C3), sem UMA
#      chamada HTTP a mais.
#
# Tambem corrige a causa das falhas diagnosticadas nesta VM: o job batia nas
# sessoes declaradas nas caixas (`spx`, que nao existe mais -> 422 em ~5s; e
# `simplexteste`, parada -> 422 em ~10s, estourando o timeout de 8s e virando
# Net::ReadTimeout). Agora consultamos `GET /api/sessions` uma vez e so batemos
# em sessao WORKING, com timeout maior para o endpoint pesado.
class Waha::RefreshGroupsJob < ApplicationJob
  # Era :low (7a fila sob prioridade estrita no sidekiq.yml -> faminta: so roda quando
  # critical/high/medium/default/mailers/action_mailbox estao vazias). Em producao
  # carregada, o aquecimento do cache LID->PN praticamente nunca executava. Movido para
  # :scheduled_jobs (logo abaixo de :low, mas e a fila dos crons e drena de forma confiavel).
  queue_as :scheduled_jobs

  # GET /groups devolve 240 KB e leva ~2s aqui; fora do ciclo web nao ha
  # Rack::Timeout para respeitar, entao damos folga em vez de falhar por 8s.
  GROUPS_TIMEOUT = 20
  MAX_SESSIONS = 20
  MAX_CONVERSATIONS_PER_RUN = 500

  def perform
    sessions = target_sessions
    return if sessions.blank?

    service = Waha::ApiService.new(timeout: GROUPS_TIMEOUT)
    sessions.each { |session_name| refresh_session(service, session_name) }
  end

  private

  def refresh_session(service, session_name)
    groups = Array(service.get_groups(session_name)).select { |group| group.is_a?(Hash) }
    cached = Whatsapp::LidPhoneCache.write_many(session_name, Waha::GroupParticipantsParser.lid_pn_pairs(groups))
    Waha::GroupLocator.index_sessions(session_name, groups.pluck('JID'))
    synced = sync_conversations(groups)

    Rails.logger.info(
      "[RefreshGroupsJob] sessao #{session_name}: #{groups.size} grupos, #{cached} pares LID->PN em cache, #{synced} conversas atualizadas"
    )
  rescue Waha::ApiService::Error => e
    Rails.logger.warn("[RefreshGroupsJob] Failed to refresh groups for #{session_name}: #{e.message}")
  end

  # As sessoes que valem uma chamada. Sessao que nao esta WORKING so devolve 422
  # (e demora para isso), entao filtramos antes de gastar a chamada.
  # `WAHA_REFRESH_SESSIONS_DISCOVERY=false` volta ao comportamento conservador de
  # so olhar as sessoes declaradas em alguma caixa.
  def target_sessions
    declared = Inbox.where.not(waha_session_name: [nil, '']).distinct.pluck(:waha_session_name)
    working = working_sessions

    if working.nil?
      Rails.logger.warn('[RefreshGroupsJob] nao consegui listar sessoes na WAHA; usando as declaradas nas caixas')
      return declared.first(MAX_SESSIONS)
    end

    log_stale_sessions(declared - working)
    sessions = discover_sessions? ? working : (declared & working)
    sessions.first(MAX_SESSIONS)
  end

  def discover_sessions?
    ENV.fetch('WAHA_REFRESH_SESSIONS_DISCOVERY', 'true') != 'false'
  end

  def log_stale_sessions(stale)
    return if stale.blank?

    Rails.logger.warn("[RefreshGroupsJob] caixas apontam para sessoes que nao estao WORKING: #{stale.join(', ')}")
  end

  def working_sessions
    Array(Waha::ApiService.new.list_sessions).filter_map do |session|
      session['name'] if session.is_a?(Hash) && session['status'].to_s.upcase == 'WORKING'
    end
  rescue Waha::ApiService::Error => e
    Rails.logger.warn("[RefreshGroupsJob] falha ao listar sessoes da WAHA: #{e.message}")
    nil
  end

  # Casa os grupos que a WAHA devolveu com as conversas de grupo pelo JID e grava
  # o snapshot C3. Zero chamada HTTP extra — os participantes ja vieram no payload.
  def sync_conversations(groups)
    by_jid = groups.index_by { |group| group['JID'].to_s }.except('')
    return 0 if by_jid.empty?

    conversations = Conversation.joins(:contact)
                                .where(contacts: { identifier: by_jid.keys })
                                .includes(:contact)
                                .limit(MAX_CONVERSATIONS_PER_RUN)

    conversations.count { |conversation| store_snapshot(conversation, by_jid[conversation.contact.identifier.to_s]) }
  end

  def store_snapshot(conversation, group)
    return false if group.blank? || !conversation.group?

    Waha::GroupSyncService.store_snapshot(conversation, group).present?
  rescue StandardError => e
    Rails.logger.warn("[RefreshGroupsJob] falha ao gravar snapshot da conversa #{conversation.id}: #{e.message}")
    false
  end
end
