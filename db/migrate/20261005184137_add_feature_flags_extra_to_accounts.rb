class AddFeatureFlagsExtraToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :feature_flags_extra, :bigint, default: 0, null: false, if_not_exists: true
  end
end
