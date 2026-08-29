# Mesmo caso do 20260324070820: coluna presente no schema.rb e no banco, arquivo ausente.
class AddSecretToChannelApi < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_api, :secret, :string, if_not_exists: true
  end
end
