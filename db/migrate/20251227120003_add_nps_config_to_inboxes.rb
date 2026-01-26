class AddNpsConfigToInboxes < ActiveRecord::Migration[7.0]
  def change
    add_column :inboxes, :nps_survey_enabled, :boolean, default: false
    add_column :inboxes, :nps_config, :jsonb, default: {}, null: false
  end
end
