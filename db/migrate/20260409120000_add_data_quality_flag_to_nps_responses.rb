class AddDataQualityFlagToNpsResponses < ActiveRecord::Migration[7.0]
  def change
    add_column :nps_responses, :data_quality_flag, :string
    add_column :nps_responses, :flag_reason, :string
    add_column :nps_responses, :flagged_at, :datetime
  end
end
