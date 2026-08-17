class Conversations::UnreadCounts::Builder
  BATCH_SIZE = 1000

  attr_reader :account

  def initialize(account)
    @account = account
  end

  def build_base!
    store.clear_account!(account.id)
    write_memberships(assignment: false)
    store.mark_base_ready!(account.id)
  end

  def build_assignment!
    store.clear_assignment!(account.id)
    write_memberships(assignment: true)
    store.mark_assignment_ready!(account.id)
  end

  def build_all!
    build_base!
    build_assignment!
  end

  private

  def write_memberships(assignment:)
    unread_conversations.in_batches(of: BATCH_SIZE) do |relation|
      columns = %i[id inbox_id assignee_id cached_label_list team_id]
      memberships = relation.pluck(*columns).map do |id, inbox_id, assignee_id, cached_label_list, team_id|
        {
          conversation_id: id,
          inbox_id: inbox_id,
          assignee_id: assignee_id,
          team_id: team_id,
          label_ids: label_ids_for(cached_label_list)
        }
      end

      store.add_memberships(account_id: account.id, memberships: memberships, assignment: assignment)
    end
  end

  # ChatSPX (item 23): NÃO usar `.joins(:messages)` aqui. O nosso `Conversation has_many :messages`
  # tem scope INSTANCE-DEPENDENT (`app/models/conversation.rb:168` — o lambda do
  # `team_message_isolation`, que é isolamento por time e é nosso), e o Rails proíbe JOIN em
  # associação instance-dependent: `ArgumentError: association scope 'messages' is instance
  # dependent`. Este arquivo é novo do upstream e trouxe o `joins(:messages)`; hoje é latente
  # (`conversation_unread_counts` / `unread_count_for_filters` estão `enabled: false` e o caminho é
  # gated por `feature_enabled?`), mas vira 500 no dia em que alguém ligar a flag para um cliente
  # com isolamento por time. O EXISTS correlacionado abaixo tem a MESMA semântica — conversa com ao
  # menos uma mensagem incoming da conta, mais nova que `agent_last_seen_at` (ou sem ele) — sem
  # tocar a associação, e dispensa o `.distinct`.
  def unread_conversations
    account.conversations.open.where(
      Message.incoming.reorder(nil).where(account_id: account.id)
             .where(Message.arel_table[:conversation_id].eq(Conversation.arel_table[:id]))
             .where(unread_since_last_seen_condition).arel.exists
    )
  end

  def unread_since_last_seen_condition
    conversations = Conversation.arel_table
    messages = Message.arel_table

    conversations[:agent_last_seen_at].eq(nil).or(messages[:created_at].gt(conversations[:agent_last_seen_at]))
  end

  def label_ids_for(cached_label_list)
    label_titles = cached_label_list.to_s.split(',').map(&:strip).compact_blank
    labels_by_title.values_at(*label_titles).compact
  end

  def labels_by_title
    @labels_by_title ||= account.labels.pluck(:title, :id).to_h
  end

  def store
    ::Conversations::UnreadCounts::Store
  end
end
