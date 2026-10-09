class AddArchivedAtToInternalChannelMembers < ActiveRecord::Migration[7.1]
  # Aditiva: "Arquivar conversa" do chat interno é por pessoa (o membro); nulo = na lista.
  def change
    add_column :internal_channel_members, :archived_at, :datetime
  end
end
