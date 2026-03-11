class AddTrigramIndexesToContacts < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :contacts, :name,
              using: :gin,
              opclass: :gin_trgm_ops,
              name: 'idx_contacts_name_trgm',
              algorithm: :concurrently,
              if_not_exists: true

    add_index :contacts, :email,
              using: :gin,
              opclass: :gin_trgm_ops,
              name: 'idx_contacts_email_trgm',
              algorithm: :concurrently,
              if_not_exists: true

    add_index :contacts, :phone_number,
              using: :gin,
              opclass: :gin_trgm_ops,
              name: 'idx_contacts_phone_trgm',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
