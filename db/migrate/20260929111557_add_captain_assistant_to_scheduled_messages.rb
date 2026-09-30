class AddCaptainAssistantToScheduledMessages < ActiveRecord::Migration[7.1]
  def change
    add_reference :scheduled_messages, :captain_assistant, index: true, if_not_exists: true
  end
end
