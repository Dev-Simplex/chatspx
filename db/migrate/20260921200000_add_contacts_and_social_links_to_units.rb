# frozen_string_literal: true

# A filial costuma ter mais de um número (vendas, locação, o WhatsApp do plantão) e um punhado de
# links. Duas listas jsonb em vez de tabela: são poucos itens, sempre editados em bloco com o resto
# do cadastro, e nunca consultados por si.
#
# `phone` continua existindo e passa a ser o PRIMEIRO contato da lista (o model mantém os dois em
# dia): a lista de unidades, a API e quem já lê o campo seguem funcionando sem saber da mudança.
class AddContactsAndSocialLinksToUnits < ActiveRecord::Migration[7.1]
  def up
    add_column :units, :contacts, :jsonb, default: [], null: false
    add_column :units, :social_links, :jsonb, default: [], null: false

    execute <<~SQL.squish
      UPDATE units
         SET contacts = jsonb_build_array(jsonb_build_object('label', '', 'phone', phone))
       WHERE phone IS NOT NULL AND phone <> ''
    SQL
  end

  def down
    remove_column :units, :contacts
    remove_column :units, :social_links
  end
end
