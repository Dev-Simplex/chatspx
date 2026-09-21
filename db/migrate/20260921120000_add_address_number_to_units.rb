# Numero da casa separado do endereco. O ViaCEP preenche `address` com "logradouro - bairro" e
# sobrescreve o campo inteiro, entao quem digitava o numero ali dentro o perdia ao mexer no CEP.
#
# `string` e nao integer: precisa aceitar "S/N", "123-A" e "Km 12".
class AddAddressNumberToUnits < ActiveRecord::Migration[7.1]
  def change
    add_column :units, :address_number, :string, if_not_exists: true
  end
end
