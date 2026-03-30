class DeleteObjectJob < ApplicationJob
  queue_as :low

  BATCH_SIZE = 5_000

  ALLOWED_OBJECT_TYPES = %w[
    Account Inbox Conversation Contact User
    AgentBot Label SlaPolicy CustomAttributeDefinition
  ].freeze

  def perform(object_type, object_id, user_id = nil, ip = nil)
    return unless ALLOWED_OBJECT_TYPES.include?(object_type)

    object = object_type.constantize.find_by(id: object_id)
    return unless object

    user = user_id ? User.find_by(id: user_id) : nil

    # Pre-purge heavy associations for large objects to avoid
    # timeouts & race conditions due to destroy_async fan-out.
    purge_heavy_associations(object)
    object.destroy!
    process_post_deletion_tasks(object, user, ip)
  end

  def process_post_deletion_tasks(object, user, ip); end

  private

  def heavy_associations
    {
      Account => %i[conversations contacts inboxes reporting_events],
      Inbox => %i[conversations contact_inboxes reporting_events]
    }.freeze
  end

  def purge_heavy_associations(object)
    klass = heavy_associations.keys.find { |k| object.is_a?(k) }
    return unless klass

    heavy_associations[klass].each do |assoc|
      next unless object.respond_to?(assoc)

      batch_destroy(object.public_send(assoc))
    end
  end

  def batch_destroy(relation)
    relation.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      batch.each(&:destroy!)
    end
  end
end

DeleteObjectJob.prepend_mod_with('DeleteObjectJob')
