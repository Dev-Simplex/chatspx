class AddRequiredAndHiddenToCustomAttributeDefinitions < ActiveRecord::Migration[7.1]
  def up
    add_column :custom_attribute_definitions, :required, :boolean, default: false, null: false
    add_column :custom_attribute_definitions, :hidden, :boolean, default: false, null: false

    backfill_required_from_account_settings
  end

  def down
    remove_column :custom_attribute_definitions, :required
    remove_column :custom_attribute_definitions, :hidden
  end

  private

  # A obrigatoriedade morava em `account.settings.conversation_required_attributes`
  # (por conta, só de conversa). Sem este backfill, a conta que já tinha atributos
  # obrigatórios configurados os perderia em silêncio ao ganhar a coluna.
  def backfill_required_from_account_settings
    Account.find_each do |account|
      keys = account.settings['conversation_required_attributes']
      next if keys.blank?

      # rubocop:disable Rails/SkipsModelValidations
      account.custom_attribute_definitions
             .where(attribute_model: :conversation_attribute, attribute_key: keys)
             .update_all(required: true)
      # rubocop:enable Rails/SkipsModelValidations
    end
  end
end
