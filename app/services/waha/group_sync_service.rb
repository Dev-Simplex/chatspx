# frozen_string_literal: true

# Sincroniza os integrantes de um grupo de WhatsApp (WAHA) para dentro da conversa,
# gravando o snapshot em `conversation.additional_attributes['waha_group']`
# (contrato C3). NAO ha migration: a coluna jsonb ja existe e ja e serializada para
# o front por `_conversation.json.jbuilder`.
#
# Quando sincroniza — os dois caminhos, de proposito:
#   * periodico e de graca: o Waha::RefreshGroupsJob ja busca GET /groups a cada
#     30 min e essa resposta ja traz os participantes de TODOS os grupos. Ele
#     alimenta os snapshots sem UMA chamada HTTP a mais (ver
#     RefreshGroupsJob#sync_conversations).
#   * sob demanda: o agente aperta "Sincronizar agora" no painel e o endpoint
#     chama este servico com force: true.
# Abrir a conversa NAO dispara sync sozinho — seria uma chamada a WAHA por
# abertura de tela, justamente o desperdicio que viemos consertar.
#
# REQUISITO DURO: falha da WAHA nunca quebra a tela. Este servico nunca levanta;
# devolve um resultado com `ok: false` e, o mais importante, NAO escreve nada no
# jsonb quando falha — o snapshot anterior (se existir) permanece intacto, e a
# ausencia de snapshot continua significando "nunca sincronizado" para o front.
class Waha::GroupSyncService
  # Frescor do snapshot: dentro dessa janela um sync nao forcado e no-op.
  SNAPSHOT_TTL = 15.minutes
  # Piso anti-marreta do botao "Sincronizar agora" (por conversa).
  FORCE_MIN_INTERVAL = 30
  # Cool-off por sessao apos timeout/erro de conexao — mesmo padrao do
  # Waha::MessageStatusSyncService.
  CIRCUIT_TTL = 60
  # Quantas sessoes candidatas tentamos no maximo numa execucao.
  MAX_SESSION_ATTEMPTS = 2

  Result = Struct.new(:ok, :status, :reason, :snapshot, keyword_init: true) do
    def ok? = ok
  end

  def initialize(conversation, force: false)
    @conversation = conversation
    @force = force
  end

  def perform
    group_id = Waha::GroupLocator.group_id(@conversation)
    return result(false, 'skipped', 'not_a_group') if group_id.blank?

    throttle_guard || fetch_and_store(group_id)
  rescue StandardError => e
    # Rede de seguranca: nada aqui pode subir para o controller/job.
    Rails.logger.warn("[WAHA][GroupSync] erro inesperado na conversa #{@conversation&.id}: #{e.class}: #{e.message}")
    result(false, 'failed', 'unexpected_error', current_snapshot)
  end

  # Grava um snapshot ja pronto (usado pelo RefreshGroupsJob, que recebe os
  # participantes de brinde no payload de /groups). Devolve o snapshot gravado ou
  # nil quando nao havia nada de novo.
  def self.store_snapshot(conversation, raw_participants)
    participants = Waha::GroupParticipantsParser.parse(raw_participants)
    return nil if participants.empty?

    snapshot = build_snapshot(participants)
    return nil if unchanged?(conversation, snapshot)

    write_snapshot(conversation, snapshot)
    snapshot
  end

  def self.build_snapshot(participants)
    {
      'participants' => participants,
      'count' => participants.size,
      'synced_at' => Time.current.utc.iso8601
    }
  end

  # Compara ignorando `synced_at`: reescrever o mesmo snapshot a cada 30 min so
  # geraria escrita no banco sem informacao nova.
  def self.unchanged?(conversation, snapshot)
    previous = conversation.additional_attributes&.dig('waha_group')
    return false if previous.blank?

    previous['participants'] == snapshot['participants']
  end

  # Merge atomico dentro do Postgres (mesmo padrao do
  # Conversations::UserSettingUpdateService): substitui so o no 'waha_group' e
  # nao pisa em nada que outro processo tenha escrito em additional_attributes.
  def self.write_snapshot(conversation, snapshot)
    sql = <<~SQL.squish
      additional_attributes = jsonb_set(
        coalesce(additional_attributes, '{}'::jsonb), ARRAY['waha_group'], ?::jsonb, true
      )
    SQL
    Conversation.where(id: conversation.id).update_all([sql, snapshot.to_json]) # rubocop:disable Rails/SkipsModelValidations
    conversation.additional_attributes = (conversation.additional_attributes || {}).merge('waha_group' => snapshot)
    broadcast_snapshot(conversation)
    snapshot
  end

  # O merge acima e feito com `update_all` para nao pisar em escritas
  # concorrentes — e `update_all` nao dispara callback nenhum, entao o painel
  # aberto nunca ficaria sabendo. Emitimos o evento a mao para que a lista de
  # integrantes se atualize sozinha na tela de quem esta com a conversa aberta.
  #
  # So chega aqui quando o snapshot MUDOU de fato (`unchanged?` barra o resto),
  # entao isso nao vira ruido de websocket a cada ciclo do RefreshGroupsJob.
  def self.broadcast_snapshot(conversation)
    # Reusa o dispatch do proprio modelo (privado) em vez de montar o payload a
    # mao: ele ja preenche performed_by e notifiable_assignee_change?, que o
    # ActionCableListener espera encontrar.
    # Constante qualificada de proposito: ela mora em Events::Types, que este
    # servico nao inclui — referenciar solta levanta NameError e o snapshot fica
    # gravado sem chegar na tela.
    conversation.send(:dispatcher_dispatch, Events::Types::CONVERSATION_UPDATED, { 'additional_attributes' => true })
  rescue StandardError => e
    Rails.logger.warn("[WAHA][GroupSync] snapshot gravado mas nao propagado (conversa #{conversation.id}): #{e.class} #{e.message}")
  end

  private

  # Snapshot fresco nao vale uma chamada; e o botao "Sincronizar agora" tem piso
  # de FORCE_MIN_INTERVAL segundos por conversa.
  def throttle_guard
    return result(true, 'cached', nil, current_snapshot) if !@force && fresh?
    return result(false, 'throttled', 'force_throttled', current_snapshot) if @force && force_throttled?

    nil
  end

  def fetch_and_store(group_id)
    session_name, raw = fetch_participants(group_id)
    return result(false, 'failed', @failure_reason || 'waha_unavailable', current_snapshot) if raw.blank?

    participants = Waha::GroupParticipantsParser.parse(raw)
    return result(false, 'failed', 'empty_participants', current_snapshot) if participants.empty?

    cache_side_effects(session_name, group_id, participants)
    snapshot = self.class.build_snapshot(participants)
    self.class.write_snapshot(@conversation, snapshot)
    mark_forced_at if @force
    result(true, 'synced', nil, snapshot)
  end

  # Tenta as sessoes candidatas em ordem de confianca. Sessao com circuito aberto
  # e pulada sem custo; timeout/erro de conexao abre o circuito e passa para a
  # proxima.
  def fetch_participants(group_id)
    usable_sessions(group_id).each do |session_name|
      raw = fetch_from_session(session_name, group_id)
      return [session_name, raw] if raw.present?
    end

    [nil, nil]
  end

  # Candidatas menos as que estao em cool-off, limitadas a MAX_SESSION_ATTEMPTS.
  def usable_sessions(group_id)
    candidates = Waha::GroupLocator.session_candidates(@conversation, group_id)
    if candidates.empty?
      @failure_reason = 'no_session'
      return []
    end

    usable = candidates.reject { |session_name| circuit_open?(session_name) }
    @failure_reason = 'circuit_open' if usable.empty?
    usable.first(MAX_SESSION_ATTEMPTS)
  end

  def fetch_from_session(session_name, group_id)
    raw = api.get_group_participants(session_name, group_id)
    close_circuit(session_name)
    raw
  rescue Waha::ApiService::ConnectionError => e
    open_circuit(session_name)
    Rails.logger.warn("[WAHA][GroupSync] timeout/conexao na sessao #{session_name}; circuito aberto por #{CIRCUIT_TTL}s: #{e.message}")
    @failure_reason = 'waha_unavailable'
    nil
  rescue Waha::ApiService::Error => e
    Rails.logger.warn("[WAHA][GroupSync] sessao #{session_name} nao respondeu o grupo #{group_id}: #{e.message}")
    @failure_reason = 'waha_error'
    nil
  end

  # Aproveita a mesma resposta para alimentar o cache LID->PN (lido pela ingestao)
  # e o indice grupo -> sessao (lido pelo proprio locator na proxima vez).
  def cache_side_effects(session_name, group_id, participants)
    pairs = participants.filter_map { |p| [p['lid'], p['phone']] if p['lid'].present? && p['phone'].present? }
    Whatsapp::LidPhoneCache.write_many(session_name, pairs)
    Waha::GroupLocator.index_sessions(session_name, [group_id])
  rescue StandardError => e
    Rails.logger.warn("[WAHA][GroupSync] falha ao alimentar cache da sessao #{session_name}: #{e.message}")
  end

  def api
    @api ||= Waha::ApiService.new
  end

  def current_snapshot
    @conversation&.additional_attributes&.dig('waha_group')
  end

  def fresh?
    synced_at = current_snapshot&.dig('synced_at')
    return false if synced_at.blank?

    Time.zone.parse(synced_at.to_s) > SNAPSHOT_TTL.ago
  rescue ArgumentError, TypeError
    false
  end

  def force_throttled?
    Redis::Alfred.get(force_key).present?
  end

  def mark_forced_at
    Redis::Alfred.setex(force_key, '1', FORCE_MIN_INTERVAL)
  end

  def force_key
    "waha:group_sync:forced:#{@conversation.id}"
  end

  def circuit_open?(session_name)
    Redis::Alfred.get(circuit_key(session_name)).present?
  end

  def open_circuit(session_name)
    Redis::Alfred.setex(circuit_key(session_name), '1', CIRCUIT_TTL)
  end

  def close_circuit(session_name)
    Redis::Alfred.delete(circuit_key(session_name))
  end

  def circuit_key(session_name)
    "waha:group_sync:circuit:#{session_name}"
  end

  def result(success, status, reason, snapshot = nil)
    Result.new(ok: success, status: status, reason: reason, snapshot: snapshot)
  end
end
