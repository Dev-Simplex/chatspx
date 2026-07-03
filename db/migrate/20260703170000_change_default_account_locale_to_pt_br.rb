# frozen_string_literal: true

# Padrão de idioma das contas passa a ser pt-BR (chave 16 do enum locale).
# Antes era 0 (English). Assim, contas criadas sem locale explícito (seed, setup,
# Account.create!) nascem em português. Ver AccountBuilder e config.i18n.default_locale.
class ChangeDefaultAccountLocaleToPtBr < ActiveRecord::Migration[7.1]
  def up
    change_column_default :accounts, :locale, from: 0, to: 16
  end

  def down
    change_column_default :accounts, :locale, from: 16, to: 0
  end
end
