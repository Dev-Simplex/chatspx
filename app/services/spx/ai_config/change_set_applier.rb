# Receptor de change-sets de comportamento das IAs (Captain) — o que APLICA, na VM,
# uma mudanca APROVADA pelo control plane (Almirante). Transacional, idempotente,
# com snapshot + auditoria (AiConfigChange) e rollback. So mexe em config-no-banco
# que e LIVE por request (nao toca codigo/template — isso e deploy).
#
# Escopo: update_instructions, add_faq, arm_tool/disarm_tool, set_credential,
#         update_behavior, set_eligibility.
#
# Uso:
#   applier = Spx::AiConfig::ChangeSetApplier.new(change_set_hash)
#   applier.dry_run            # => diff, sem escrever
#   applier.apply!             # => AiConfigChange (transacional/idempotente/auditado)
#   Spx::AiConfig::ChangeSetApplier.revert!(change_set_id)  # restaura o snapshot
#
# change_set (Hash, chaves string ou symbol):
#   { change_set_id:, account_id:, author:, approved_by:,
#     operations: [ { type:, assistant_id:, ... } ] }
module Spx
  module AiConfig
    class ChangeSetApplier
      SUPPORTED_OPERATIONS = %w[
        update_instructions add_faq arm_tool disarm_tool
        set_credential update_behavior set_eligibility upsert_custom_tool
      ].freeze

      # Ops que escrevem no escopo de UM assistant (exigem assistant_id). set_credential e
      # upsert_custom_tool sao account-scoped (account_integrations / captain_custom_tools)
      # — NAO exigem assistant_id.
      ASSISTANT_SCOPED_OPERATIONS = (SUPPORTED_OPERATIONS - %w[set_credential upsert_custom_tool]).freeze

      # Colunas gravaveis de captain_custom_tools via change-set (whitelist). `url`/`schema`
      # sao aceitos como aliases (contrato MCP §5) e mapeados pra endpoint_url/param_schema.
      CUSTOM_TOOL_FIELDS = %w[
        title description endpoint_url http_method auth_type auth_config
        param_schema request_template response_template copilot_only enabled
      ].freeze

      # Chaves validas do store_accessor :behavior (Captain::Assistant). Whitelist
      # impede poluir o jsonb com chave arbitraria.
      BEHAVIOR_KEYS = %w[
        debounce_seconds business_hours_config humanizer_config media_pipeline_config
        router_config copilot_trigger_config dedup_config
      ].freeze

      class InvalidChangeSet < StandardError; end
      class UnsupportedOperation < StandardError; end
      class TenantViolation < StandardError; end

      # Reverte um change-set ja aplicado restaurando o snapshot anterior.
      def self.revert!(change_set_id)
        record = AiConfigChange.find_by!(change_set_id: change_set_id)
        raise InvalidChangeSet, "change-set #{change_set_id} nao esta aplicado (status=#{record.status})" unless record.applied?

        ActiveRecord::Base.transaction do
          record.operations.each_with_index do |op, idx|
            revert_operation(op, record.snapshot_before[idx.to_s], record.result[idx.to_s], record.account_id)
          end
          record.update!(status: :reverted, reverted_at: Time.current)
        end
        record
      end

      # Revert por op — sempre na ordem reversa do apply (ver revert!). Cada caso
      # restaura o campo/hash INTEIRO guardado no snapshot (`before`), o que cobre
      # ate a remocao de chave que nao existia antes.
      def self.revert_operation(op, before, after, account_id)
        case op['type']
        when 'update_instructions'
          assistant = scoped_assistant(op['assistant_id'], account_id)
          assistant.update!(config: assistant.config.merge('instructions' => before['instructions']))
        when 'add_faq'
          faq_id = after && after['faq_id']
          Captain::AssistantResponse.where(id: faq_id, account_id: account_id).destroy_all if faq_id
        when 'arm_tool', 'disarm_tool'
          assistant = scoped_assistant(op['assistant_id'], account_id)
          assistant.update!(config: assistant.config.merge('tools' => Array(before['tools'])))
        when 'set_credential'
          revert_set_credential(op, before, account_id)
        when 'upsert_custom_tool'
          revert_upsert_custom_tool(before, after, account_id)
        when 'update_behavior'
          assistant = scoped_assistant(op['assistant_id'], account_id)
          assistant.update!(behavior: before['behavior'] || {})
        when 'set_eligibility'
          assistant = scoped_assistant(op['assistant_id'], account_id)
          reconcile_inboxes!(assistant, Array(before['inbox_ids']).map(&:to_i))
        end
      end
      private_class_method :revert_operation

      def self.revert_set_credential(op, before, account_id)
        account = Account.find(account_id)
        integration = account.account_integrations.find_by(provider: op['provider'].to_s)
        if before['existed']
          integration&.update!(settings: before['settings'], enabled: before['enabled'])
        else
          integration&.destroy!
        end
      end
      private_class_method :revert_set_credential

      # Custom tool: snapshot wholesale do registro (before['attributes']). Editado -> restaura
      # os atributos guardados; criado do zero (before['existed']==false) -> destroi.
      def self.revert_upsert_custom_tool(before, after, account_id)
        account = Account.find(account_id)
        record_id = after && after['custom_tool_id']
        record = account.captain_custom_tools.find_by(id: record_id) if record_id
        return if record.nil?

        if before && before['existed']
          record.update!(before['attributes'].except('id', 'account_id', 'created_at', 'updated_at'))
        else
          record.destroy!
        end
      end
      private_class_method :revert_upsert_custom_tool

      def self.scoped_assistant(assistant_id, account_id)
        Captain::Assistant.find_by!(id: assistant_id, account_id: account_id)
      end
      private_class_method :scoped_assistant

      # Reconcilia o conjunto de CaptainInbox do assistant pra bater EXATAMENTE com `target`.
      def self.reconcile_inboxes!(assistant, target)
        current = assistant.captain_inboxes.pluck(:inbox_id)
        to_remove = current - target
        to_add = target - current
        CaptainInbox.where(captain_assistant_id: assistant.id, inbox_id: to_remove).delete_all if to_remove.any?
        to_add.each { |inbox_id| CaptainInbox.create!(captain_assistant_id: assistant.id, inbox_id: inbox_id) }
      end
      private_class_method :reconcile_inboxes!

      def initialize(change_set)
        @cs = change_set.deep_stringify_keys
        validate_shape!
      end

      # O que MUDARIA, sem escrever nada (pro Almirante renderizar o diff pro pleno).
      def dry_run
        @cs['operations'].map { |op| diff_for(op) }
      end

      # Aplica tudo-ou-nada. Reaplicar o mesmo change_set_id e no-op (idempotente).
      # Em falha: rollback da txn + grava status:failed numa txn SEPARADA, antes de re-raise.
      def apply!
        existing = AiConfigChange.find_by(change_set_id: change_set_id)
        return existing if existing&.applied?

        snapshot = {}
        result = {}
        ActiveRecord::Base.transaction do
          @cs['operations'].each_with_index do |op, idx|
            before, after = apply_operation(op)
            snapshot[idx.to_s] = before
            result[idx.to_s] = after
          end
          persist_record(existing, snapshot, result)
        end
      rescue StandardError => e
        persist_failure!(e)
        raise
      end

      private

      def persist_record(existing, snapshot, result)
        record = existing || AiConfigChange.new(change_set_id: change_set_id)
        record.update!(
          account_id: account_id,
          assistant_id: primary_assistant_id,
          author: @cs['author'],
          approved_by: @cs['approved_by'],
          operations: @cs['operations'],
          snapshot_before: snapshot,
          result: result,
          status: :applied,
          error_message: nil,
          applied_at: Time.current,
          reverted_at: nil
        )
        record
      end

      # A txn do apply! ja sofreu rollback ao chegar aqui (estamos no rescue, fora dela);
      # gravar a falha numa txn nova garante que o rastro NAO some junto. Idempotente
      # por change_set_id. Nunca mascara o erro original — falha ao auditar so loga.
      def persist_failure!(error)
        ActiveRecord::Base.transaction do
          record = AiConfigChange.find_by(change_set_id: change_set_id) ||
                   AiConfigChange.new(change_set_id: change_set_id)
          record.update!(
            account_id: account_id,
            assistant_id: primary_assistant_id,
            author: @cs['author'],
            approved_by: @cs['approved_by'],
            operations: @cs['operations'],
            status: :failed,
            error_message: error.message
          )
        end
      rescue StandardError => e
        Rails.logger.error(
          "[Spx::AiConfig] falha ao gravar status:failed de #{change_set_id}: #{e.message}"
        )
      end

      def apply_operation(op)
        case op['type']
        when 'update_instructions' then apply_update_instructions(op)
        when 'add_faq' then apply_add_faq(op)
        when 'arm_tool' then apply_arm_tool(op, arm: true)
        when 'disarm_tool' then apply_arm_tool(op, arm: false)
        when 'set_credential' then apply_set_credential(op)
        when 'upsert_custom_tool' then apply_upsert_custom_tool(op)
        when 'update_behavior' then apply_update_behavior(op)
        when 'set_eligibility' then apply_set_eligibility(op)
        else raise UnsupportedOperation, op['type'].to_s
        end
      end

      def apply_update_instructions(op)
        assistant = find_assistant!(op['assistant_id'])
        before = { 'instructions' => assistant.config['instructions'] }
        assistant.update!(config: assistant.config.merge('instructions' => op['instructions']))
        [before, { 'instructions' => op['instructions'] }]
      end

      def apply_add_faq(op)
        assistant = find_assistant!(op['assistant_id'])
        faq = assistant.responses.create!(question: op['question'], answer: op['answer'], status: :approved)
        [nil, { 'faq_id' => faq.id }]
      end

      # arm/disarm tool built-in em assistant.config['tools'] (array de ids string).
      # Snapshot wholesale da lista inteira -> revert trivial e identico pros dois.
      def apply_arm_tool(op, arm:)
        assistant = find_assistant!(op['assistant_id'])
        tool_id = op['tool_id'].to_s
        raise InvalidChangeSet, "tool_id ausente na op #{op['type']}" if tool_id.blank?
        unless assistant.available_tool_ids.include?(tool_id)
          raise InvalidChangeSet, "tool '#{tool_id}' nao disponivel para assistant #{assistant.id}"
        end

        before = { 'tools' => Array(assistant.config['tools']).map(&:to_s) }
        new_tools = arm ? (before['tools'] + [tool_id]).uniq : (before['tools'] - [tool_id])
        assistant.update!(config: assistant.config.merge('tools' => new_tools))
        [before, { 'tools' => new_tools }]
      end

      # Credencial de integracao da conta (account_integrations), account-scoped.
      def apply_set_credential(op)
        provider = op['provider'].to_s
        raise InvalidChangeSet, "provider '#{provider}' nao suportado" unless AccountIntegration::SUPPORTED_PROVIDERS.include?(provider)

        integration = account.account_integrations.find_or_initialize_by(provider: provider)
        before = {
          'existed' => integration.persisted?,
          'settings' => integration.settings&.dup,
          'enabled' => integration.enabled
        }
        integration.settings = merge_credential_settings(integration, op['settings'])
        integration.enabled = ActiveModel::Type::Boolean.new.cast(op['enabled']) unless op['enabled'].nil?
        integration.save!
        [before, { 'provider' => provider, 'integration_id' => integration.id }]
      end

      # Merge submetido sobre o armazenado; pula secret mascarado/em branco (mesma regra
      # do IntegrationsController#merged_settings) — re-post de valor mascarado nao apaga segredo.
      def merge_credential_settings(integration, submitted)
        current = (integration.settings || {}).dup
        return current if submitted.blank?

        submitted.to_h.each do |key, value|
          next if AccountIntegration::SECRET_KEYS.include?(key.to_s) && masked_or_blank?(value)

          current[key.to_s] = value
        end
        current
      end

      def masked_or_blank?(value)
        value.blank? || value.to_s.include?('*')
      end

      # Custom tool da conta (captain_custom_tools), account-scoped. Cria ou edita.
      # before = snapshot wholesale do registro (atributos inteiros) pro revert restaurar
      # ou destruir. Falha de validacao do model vira InvalidChangeSet (422 no controller).
      def apply_upsert_custom_tool(op)
        record = locate_custom_tool(op)
        before = custom_tool_snapshot(record)
        record.account = account
        record.assign_attributes(custom_tool_attrs(op))
        record.save!
        [before, { 'custom_tool_id' => record.id, 'slug' => record.slug }]
      rescue ActiveRecord::RecordInvalid => e
        raise InvalidChangeSet, "custom tool invalida: #{e.message}"
      end

      # Alvo do upsert: por id, senao por slug (find_or_initialize), senao novo registro.
      def locate_custom_tool(op)
        tool = op['tool'] || {}
        if tool['id'].present?
          account.captain_custom_tools.find(tool['id'])
        elsif tool['slug'].present?
          account.captain_custom_tools.find_or_initialize_by(slug: tool['slug'])
        else
          account.captain_custom_tools.new
        end
      end

      def custom_tool_snapshot(record)
        return { 'existed' => false } unless record.persisted?

        { 'existed' => true, 'id' => record.id,
          'attributes' => record.attributes.except('created_at', 'updated_at') }
      end

      # Whitelist + aliases do contrato MCP (`url`->endpoint_url, `schema`->param_schema).
      def custom_tool_attrs(op)
        tool = (op['tool'] || {}).dup
        tool['endpoint_url'] = tool['url'] if tool['endpoint_url'].blank? && tool.key?('url')
        tool['param_schema'] = tool['schema'] if tool['param_schema'].blank? && tool.key?('schema')
        tool.slice(*CUSTOM_TOOL_FIELDS)
      end

      # behavior store_accessor — snapshot do hash INTEIRO (revert exato mesmo p/ chave nova).
      def apply_update_behavior(op)
        assistant = find_assistant!(op['assistant_id'])
        changes = op['behavior']
        raise InvalidChangeSet, 'behavior ausente ou invalido' unless changes.is_a?(Hash) && changes.present?

        unknown = changes.keys.map(&:to_s) - BEHAVIOR_KEYS
        raise InvalidChangeSet, "chaves de behavior invalidas: #{unknown.join(', ')}" if unknown.any?

        before = { 'behavior' => (assistant.behavior || {}).dup }
        assistant.update!(behavior: (assistant.behavior || {}).merge(changes))
        [before, { 'behavior' => changes }]
      end

      # Elegibilidade: CaptainInbox (join captain_assistant_id + inbox_id).
      def apply_set_eligibility(op)
        assistant = find_assistant!(op['assistant_id'])
        desired = Array(op['inbox_ids']).map(&:to_i).uniq

        valid_ids = account.inboxes.where(id: desired).pluck(:id)
        raise TenantViolation, "inbox(es) #{(desired - valid_ids).inspect} nao pertencem a conta #{account_id}" if valid_ids.length != desired.length

        before = { 'inbox_ids' => assistant.captain_inboxes.pluck(:inbox_id) }
        self.class.send(:reconcile_inboxes!, assistant, desired)
        [before, { 'inbox_ids' => desired }]
      end

      def diff_for(op)
        case op['type']
        when 'update_instructions'
          assistant = find_assistant!(op['assistant_id'])
          { type: op['type'], assistant_id: assistant.id, field: 'config.instructions',
            before: assistant.config['instructions'], after: op['instructions'] }
        when 'add_faq'
          assistant = find_assistant!(op['assistant_id'])
          { type: op['type'], assistant_id: assistant.id, field: 'faq', before: nil,
            after: { question: op['question'], answer: op['answer'] } }
        when 'arm_tool', 'disarm_tool'
          diff_arm_tool(op)
        when 'set_credential'
          diff_set_credential(op)
        when 'upsert_custom_tool'
          diff_upsert_custom_tool(op)
        when 'update_behavior'
          assistant = find_assistant!(op['assistant_id'])
          keys = Array(op['behavior']).to_h.keys.map(&:to_s)
          { type: op['type'], assistant_id: assistant.id, field: 'behavior',
            before: (assistant.behavior || {}).slice(*keys), after: op['behavior'] }
        when 'set_eligibility'
          assistant = find_assistant!(op['assistant_id'])
          { type: op['type'], assistant_id: assistant.id, field: 'eligibility.inbox_ids',
            before: assistant.captain_inboxes.pluck(:inbox_id),
            after: Array(op['inbox_ids']).map(&:to_i).uniq }
        else
          raise UnsupportedOperation, op['type'].to_s
        end
      end

      def diff_arm_tool(op)
        assistant = find_assistant!(op['assistant_id'])
        current = Array(assistant.config['tools']).map(&:to_s)
        tool_id = op['tool_id'].to_s
        after = op['type'] == 'arm_tool' ? (current + [tool_id]).uniq : (current - [tool_id])
        { type: op['type'], assistant_id: assistant.id, field: 'config.tools',
          before: current, after: after }
      end

      # Diff de credencial SEMPRE mascarado (SECRET_KEYS) — nunca vaza vista_api_key/google_maps_key.
      def diff_set_credential(op)
        provider = op['provider'].to_s
        integration = account.account_integrations.find_by(provider: provider)
        stored = integration&.settings || {}
        merged = merge_credential_settings(integration || account.account_integrations.new(provider: provider), op['settings'])
        { type: op['type'], field: "integration.#{provider}.settings",
          before: mask_settings(stored), after: mask_settings(merged) }
      end

      def mask_settings(settings)
        (settings || {}).each_with_object({}) do |(key, value), acc|
          acc[key.to_s] = if AccountIntegration::SECRET_KEYS.include?(key.to_s)
                            AccountIntegration.mask_secret(value)
                          else
                            value
                          end
        end
      end

      # Diff de custom tool — auth_config SEMPRE redigido (token/password/api_key nunca vaza).
      def diff_upsert_custom_tool(op)
        record = locate_custom_tool(op)
        { type: op['type'], field: 'captain_custom_tool',
          target_slug: record.slug, existed: record.persisted?,
          before: record.persisted? ? mask_custom_tool(record.attributes) : nil,
          after: mask_custom_tool(custom_tool_attrs(op)) }
      end

      def mask_custom_tool(attrs)
        attrs = attrs.respond_to?(:to_h) ? attrs.to_h : attrs
        masked = attrs.slice(*CUSTOM_TOOL_FIELDS, 'slug')
        if masked['auth_config'].is_a?(Hash) && masked['auth_config'].present?
          masked['auth_config'] = masked['auth_config'].transform_values { '***' }
        end
        masked
      end

      # Multi-tenant: o assistant TEM que pertencer a conta do change-set. Nunca cruza conta.
      def find_assistant!(assistant_id)
        Captain::Assistant.find_by!(id: assistant_id, account_id: account_id)
      rescue ActiveRecord::RecordNotFound
        raise TenantViolation, "assistant #{assistant_id} nao pertence a conta #{account_id}"
      end

      def account
        @account ||= Account.find(account_id)
      end

      def validate_shape!
        raise InvalidChangeSet, 'change_set_id ausente' if change_set_id.blank?
        raise InvalidChangeSet, 'account_id ausente' if account_id.blank?

        ops = @cs['operations']
        raise InvalidChangeSet, 'operations vazio ou invalido' if !ops.is_a?(Array) || ops.empty?

        ops.each { |op| validate_operation!(op) }
      end

      def validate_operation!(op)
        type = op['type']
        raise UnsupportedOperation, type.to_s unless SUPPORTED_OPERATIONS.include?(type)
        # assistant_id exigido POR TIPO: ops account-scoped (set_credential) ficam de fora.
        return unless ASSISTANT_SCOPED_OPERATIONS.include?(type) && op['assistant_id'].blank?

        raise InvalidChangeSet, "assistant_id ausente na op #{type}"
      end

      def change_set_id
        @cs['change_set_id']
      end

      def account_id
        @cs['account_id']
      end

      def primary_assistant_id
        @cs['operations'].filter_map { |op| op['assistant_id'] }.first
      end
    end
  end
end
