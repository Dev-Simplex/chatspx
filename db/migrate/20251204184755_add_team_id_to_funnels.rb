# frozen_string_literal: true

class AddTeamIdToFunnels < ActiveRecord::Migration[7.1]
  def change
    add_reference :funnels, :team, null: true, foreign_key: true, index: true
  end
end
