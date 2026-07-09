# Receptor de change-sets de comportamento das IAs (Captain) — o que APLICA, na VM,
# uma mudanca APROVADA pelo control plane (Almirante). Transacional, idempotente,
# com snapshot + auditoria (AiConfigChange) e rollback. So mexe em config-no-banco
# que e LIVE por request (nao toca codigo/template — isso e deploy).
#
# Escopo v1: update_instructions, add_faq. Ampliar depois (behavior/tools/eligibility).
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
      SUPPORTED_OPERATIONS = %w[update_instructions add_faq].freeze

      class InvalidChangeSet < StandardError; end
      class UnsupportedOperation < StandardError; end
      class TenantViolation < StandardError; end

      # Reverte um change-set ja aplicado restaurando o snapshot anterior.
      def self.revert!(change_set_id)
        record = AiConfigChange.find_by!(change_set_id: change_set_id)
        unless record.applied?
          raise InvalidChangeSet, "change-set #{change_set_id} nao esta aplicado (status=#{record.status})"
        end

        ActiveRecord::Base.transaction do
          record.operations.each_with_index do |op, idx|
            revert_operation(op, record.snapshot_before[idx.to_s], record.result[idx.to_s], record.account_id)
          end
          record.update!(status: :reverted, reverted_at: Time.current)
        end
        record
      end

      def self.revert_operation(op, before, after, account_id)
        case op['type']
        when 'update_instructions'
          assistant = Captain::Assistant.find_by!(id: op['assistant_id'], account_id: account_id)
          assistant.update!(config: assistant.config.merge('instructions' => before['instructions']))
        when 'add_faq'
          faq_id = after && after['faq_id']
          Captain::AssistantResponse.where(id: faq_id, account_id: account_id).destroy_all if faq_id
        end
      end
      private_class_method :revert_operation

      def initialize(change_set)
        @cs = change_set.deep_stringify_keys
        validate_shape!
      end

      # O que MUDARIA, sem escrever nada (pro Almirante renderizar o diff pro pleno).
      def dry_run
        @cs['operations'].map { |op| diff_for(op) }
      end

      # Aplica tudo-ou-nada. Reaplicar o mesmo change_set_id e no-op (idempotente).
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
          applied_at: Time.current,
          reverted_at: nil
        )
        record
      end

      def apply_operation(op)
        case op['type']
        when 'update_instructions' then apply_update_instructions(op)
        when 'add_faq' then apply_add_faq(op)
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

      def diff_for(op)
        assistant = find_assistant!(op['assistant_id'])
        case op['type']
        when 'update_instructions'
          { type: op['type'], assistant_id: assistant.id, field: 'config.instructions',
            before: assistant.config['instructions'], after: op['instructions'] }
        when 'add_faq'
          { type: op['type'], assistant_id: assistant.id, field: 'faq', before: nil,
            after: { question: op['question'], answer: op['answer'] } }
        else
          raise UnsupportedOperation, op['type'].to_s
        end
      end

      # Multi-tenant: o assistant TEM que pertencer a conta do change-set. Nunca cruza conta.
      def find_assistant!(assistant_id)
        Captain::Assistant.find_by!(id: assistant_id, account_id: account_id)
      rescue ActiveRecord::RecordNotFound
        raise TenantViolation, "assistant #{assistant_id} nao pertence a conta #{account_id}"
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
        raise InvalidChangeSet, "assistant_id ausente na op #{type}" if op['assistant_id'].blank?
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
