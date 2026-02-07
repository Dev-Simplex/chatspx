# frozen_string_literal: true

class AddAutomationTypeToFunnelStages < ActiveRecord::Migration[7.1]
  def change
    add_column :funnel_stages, :automation_type, :string, null: true
    add_index :funnel_stages, :automation_type
  end
end
