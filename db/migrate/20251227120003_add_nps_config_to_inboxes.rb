class AddNpsConfigToInboxes < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:inboxes, :nps_survey_enabled)
      add_column :inboxes, :nps_survey_enabled, :boolean, default: false
    end

    unless column_exists?(:inboxes, :nps_config)
      add_column :inboxes, :nps_config, :jsonb, default: {}, null: false
    end
  end
end
