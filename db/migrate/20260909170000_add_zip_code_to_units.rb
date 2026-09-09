# CEP da unidade. Guardado porque é o que o admin digita: o endereço, a cidade e o estado passam a
# ser preenchidos a partir dele, e sem guardar o CEP a próxima edição abriria o formulário sem ele.
#
# `string` e não integer: CEP tem zero à esquerda (01310-100) e integer comeria o zero.
class AddZipCodeToUnits < ActiveRecord::Migration[7.1]
  def change
    add_column :units, :zip_code, :string, if_not_exists: true
  end
end
