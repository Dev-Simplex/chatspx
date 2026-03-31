# Migration: add missing performance indexes identified in DB audit.
# All indexes use algorithm: :concurrently to avoid table locks.
class AddMissingPerformanceIndexes < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    # =========================================================================
    # 1. agent_bot_inboxes — zero indexes, queried by inbox/status, bot, account
    # =========================================================================
    add_index :agent_bot_inboxes, %i[inbox_id status],
              name: :idx_agent_bot_inboxes_inbox_status,
              algorithm: :concurrently,
              if_not_exists: true

    add_index :agent_bot_inboxes, :agent_bot_id,
              name: :idx_agent_bot_inboxes_agent_bot_id,
              algorithm: :concurrently,
              if_not_exists: true

    add_index :agent_bot_inboxes, :account_id,
              name: :idx_agent_bot_inboxes_account_id,
              algorithm: :concurrently,
              if_not_exists: true

    # =========================================================================
    # 2. canned_responses — queried by account and account + short_code
    # =========================================================================
    add_index :canned_responses, :account_id,
              name: :idx_canned_responses_account_id,
              algorithm: :concurrently,
              if_not_exists: true

    add_index :canned_responses, %i[account_id short_code],
              name: :idx_canned_responses_account_short_code,
              algorithm: :concurrently,
              if_not_exists: true

    # =========================================================================
    # 3. integrations_hooks — queried by account + app and inbox
    # =========================================================================
    add_index :integrations_hooks, %i[account_id app_id],
              name: :idx_integrations_hooks_account_app,
              algorithm: :concurrently,
              if_not_exists: true

    add_index :integrations_hooks, :inbox_id,
              name: :idx_integrations_hooks_inbox_id,
              algorithm: :concurrently,
              if_not_exists: true

    # =========================================================================
    # 4. folders — queried by account and category
    # =========================================================================
    add_index :folders, :account_id,
              name: :idx_folders_account_id,
              algorithm: :concurrently,
              if_not_exists: true

    add_index :folders, :category_id,
              name: :idx_folders_category_id,
              algorithm: :concurrently,
              if_not_exists: true

    # =========================================================================
    # 5. conversations — partial index for open conversation counts
    # =========================================================================
    add_index :conversations, %i[account_id inbox_id team_id assignee_id],
              name: :idx_conv_open_counts,
              where: 'status = 0',
              algorithm: :concurrently,
              if_not_exists: true

    # =========================================================================
    # 6. conversations — partial index for snoozed reopen job
    # =========================================================================
    add_index :conversations, %i[status snoozed_until],
              name: :idx_conv_snoozed_reopen,
              where: 'status = 3',
              algorithm: :concurrently,
              if_not_exists: true

    # =========================================================================
    # 7. conversations — partial index on sla_policy_id (sparse column)
    # =========================================================================
    add_index :conversations, :sla_policy_id,
              name: :idx_conv_sla_policy_id,
              where: 'sla_policy_id IS NOT NULL',
              algorithm: :concurrently,
              if_not_exists: true

    # =========================================================================
    # 8. conversations — partial index on assignee_agent_bot_id (sparse column)
    # =========================================================================
    add_index :conversations, :assignee_agent_bot_id,
              name: :idx_conv_assignee_agent_bot_id,
              where: 'assignee_agent_bot_id IS NOT NULL',
              algorithm: :concurrently,
              if_not_exists: true

    # =========================================================================
    # 9. inbox_members — reverse-leading index for user_id queries
    #    Existing unique index is (inbox_id, user_id); PermissionFilterService
    #    queries by user_id first.
    # =========================================================================
    add_index :inbox_members, %i[user_id inbox_id],
              name: :idx_inbox_members_user_inbox,
              algorithm: :concurrently,
              if_not_exists: true

    # =========================================================================
    # 10. notifications — partial composite index for unread/unsnoozed listing
    #     Existing idx_notifications_performance covers (user_id, account_id,
    #     snoozed_until, read_at) but lacks last_activity_at ordering and the
    #     partial filter that shrinks the index to only actionable rows.
    # =========================================================================
    add_index :notifications, %i[user_id account_id last_activity_at],
              name: :idx_notifications_unread_unsnoozed,
              where: 'read_at IS NULL AND snoozed_until IS NULL',
              order: { last_activity_at: :desc },
              algorithm: :concurrently,
              if_not_exists: true

    # =========================================================================
    # 11. contacts — partial index for blocked contacts subquery
    #     Replace full boolean index with a partial index covering only the
    #     true rows (typically < 1% of contacts).
    # =========================================================================
    remove_index :contacts, name: :index_contacts_on_blocked,
                            algorithm: :concurrently,
                            if_exists: true

    add_index :contacts, :id,
              name: :idx_contacts_blocked,
              where: 'blocked = true',
              algorithm: :concurrently,
              if_not_exists: true

    # =========================================================================
    # 13. messages.content_attributes — change from json to jsonb
    #     jsonb supports indexing, containment operators (@>), and is more
    #     efficient for read-heavy workloads.
    # =========================================================================
    change_column :messages, :content_attributes, :jsonb,
                  default: {}, using: 'content_attributes::jsonb'
  end

  def down
    # Reverse content_attributes back to json
    change_column :messages, :content_attributes, :json,
                  default: {}, using: 'content_attributes::text::json'

    # Remove partial blocked index, restore full boolean index
    remove_index :contacts, name: :idx_contacts_blocked,
                            algorithm: :concurrently, if_exists: true
    add_index :contacts, :blocked,
              name: :index_contacts_on_blocked,
              algorithm: :concurrently, if_not_exists: true

    remove_index :notifications, name: :idx_notifications_unread_unsnoozed,
                                 algorithm: :concurrently, if_exists: true

    remove_index :inbox_members, name: :idx_inbox_members_user_inbox,
                                 algorithm: :concurrently, if_exists: true

    remove_index :conversations, name: :idx_conv_assignee_agent_bot_id,
                                 algorithm: :concurrently, if_exists: true

    remove_index :conversations, name: :idx_conv_sla_policy_id,
                                 algorithm: :concurrently, if_exists: true

    remove_index :conversations, name: :idx_conv_snoozed_reopen,
                                 algorithm: :concurrently, if_exists: true

    remove_index :conversations, name: :idx_conv_open_counts,
                                 algorithm: :concurrently, if_exists: true

    remove_index :folders, name: :idx_folders_category_id,
                           algorithm: :concurrently, if_exists: true

    remove_index :folders, name: :idx_folders_account_id,
                           algorithm: :concurrently, if_exists: true

    remove_index :integrations_hooks, name: :idx_integrations_hooks_inbox_id,
                                      algorithm: :concurrently, if_exists: true

    remove_index :integrations_hooks, name: :idx_integrations_hooks_account_app,
                                      algorithm: :concurrently, if_exists: true

    remove_index :canned_responses, name: :idx_canned_responses_account_short_code,
                                    algorithm: :concurrently, if_exists: true

    remove_index :canned_responses, name: :idx_canned_responses_account_id,
                                    algorithm: :concurrently, if_exists: true

    remove_index :agent_bot_inboxes, name: :idx_agent_bot_inboxes_account_id,
                                     algorithm: :concurrently, if_exists: true

    remove_index :agent_bot_inboxes, name: :idx_agent_bot_inboxes_agent_bot_id,
                                     algorithm: :concurrently, if_exists: true

    remove_index :agent_bot_inboxes, name: :idx_agent_bot_inboxes_inbox_status,
                                     algorithm: :concurrently, if_exists: true
  end
end
