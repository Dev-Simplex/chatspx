class FkQueTravamExclusao < ActiveRecord::Migration[7.1]
  # Continuacao da 20260908120000. FK sem `on_delete` e RESTRICT no Postgres: quando nada limpa a
  # tabela filha antes, o DELETE do pai e recusado. Caixa, conversa e conta sao apagadas pelo
  # DeleteObjectJob em background (a API responde 200 e o objeto volta no reload); contato e
  # sincrono (500 na tela).
  #
  # Tres origens, todas medidas:
  #   - filha sem `has_many ... dependent:` no pai (auditoria de 15/09, L-1);
  #   - pai com `dependent: :destroy_async`: o Rails apaga o pai ANTES dos filhos, e o banco recusa;
  #   - filha de tabela que o proprio banco ja apaga em cascata (ex.: funnel_items sai com a
  #     conversa), onde o Rails nem participa.
  disable_ddl_transaction!

  # O filho nao faz sentido sem o pai.
  CASCADE = [
    %w[contact_flow_suppressions account_id accounts],
    %w[contact_flow_suppressions contact_id contacts],
    %w[flow_node_stats account_id accounts],
    %w[flow_node_stats flow_id flows],
    %w[flow_runs account_id accounts],
    %w[flow_runs contact_id contacts],
    %w[flow_runs flow_id flows],
    %w[flow_step_logs account_id accounts],
    %w[flow_step_logs flow_run_id flow_runs],
    %w[flow_step_logs flow_id flows],
    %w[scheduled_messages inbox_id inboxes],
    %w[scheduled_messages account_id accounts],
    %w[message_reactions message_id messages],
    %w[message_reactions account_id accounts],
    %w[captain_assistant_logs captain_assistant_id captain_assistants],
    %w[conversation_assignment_histories account_id accounts],
    %w[units account_id accounts],
    # Automacao sem etapa pode valer para qualquer etapa: nullify a espalharia pelo funil.
    %w[funnel_automations funnel_stage_id funnel_stages],
    %w[funnel_item_notes funnel_item_id funnel_items]
  ].freeze

  # Autor ou referencia, em coluna que aceita nulo: o registro fica, perde so o vinculo.
  # funnel_views: com cascade o time perderia as visoes COMPARTILHADAS de quem saiu; as
  # privadas ficam invisiveis (`visible_to` nunca casa user_id nulo).
  NULLIFY = [
    %w[funnel_items moved_by_id users],
    %w[funnel_item_notes user_id users],
    %w[funnel_views user_id users],
    %w[scheduled_messages scheduled_by_id users],
    %w[scheduled_messages message_id messages],
    %w[conversation_assignment_histories assignee_id users]
  ].freeze

  # Ja deviam ser CASCADE, mas o banco nem sempre esta assim. As duas primeiras (20260609120000 e
  # 20260702160000) tem banco com a marca da migration e a FK antiga (staging em 16/09). As quatro
  # da 20260908120000 sumiram do schema.rb, entao todo banco montado por schema:load (VM nova, CI,
  # teste) nasce sem elas. Onde ja estao certas, nao fazem nada.
  REAFIRMADAS = [
    %w[conversations contact_id contacts],
    %w[conversation_assignment_histories conversation_id conversations],
    %w[captain_assistant_logs conversation_id conversations],
    %w[flow_runs conversation_id conversations],
    %w[flow_step_logs conversation_id conversations],
    %w[message_sequence_enrollments conversation_id conversations]
  ].freeze

  def up
    (CASCADE + REAFIRMADAS).each { |alvo| trocar(*alvo, :cascade) }
    NULLIFY.each { |alvo| trocar(*alvo, :nullify) }
  end

  def down
    (CASCADE + NULLIFY).each { |alvo| trocar(*alvo, nil) }
  end

  private

  # Idempotente e sem travar escrita: a frota nao esta toda no mesmo ponto, entao pula tabela ou FK
  # que nao existe e FK que ja esta como deve. A FK volta NOT VALID e e validada em seguida, que no
  # Postgres nao bloqueia INSERT/UPDATE (conversations e grande em producao).
  def trocar(tabela, coluna, pai, acao)
    return unless table_exists?(tabela) && table_exists?(pai)

    fk = foreign_keys(tabela).find { |f| f.column == coluna && f.to_table == pai }
    return if fk.nil? || fk.on_delete == acao

    remove_foreign_key tabela, name: fk.name
    add_foreign_key tabela, pai, column: coluna, name: fk.name, on_delete: acao, validate: false
    validate_foreign_key tabela, name: fk.name
  end
end
