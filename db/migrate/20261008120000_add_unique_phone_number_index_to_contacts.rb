# SUP-1415: telefone unico por conta no BANCO. A validacao de unicidade do Rails deixava passar duas gravacoes
# simultaneas (duplo clique no "Novo contato", duas mensagens chegando juntas pela WAHA) e nasciam duas fichas
# do mesmo numero. Email e identifier ja tinham indice unico; o telefone nao.
#
# CONCURRENTLY nao trava a tabela de contatos. Rode antes `bundle exec rake contacts:telefone_duplicado` em cada
# VM: se sobrar uma duplicata, a criacao do indice falha (e nada muda).
class AddUniquePhoneNumberIndexToContacts < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :contacts, [:account_id, :phone_number], unique: true, name: 'uniq_phone_number_per_account_contact',
                                                       where: "phone_number IS NOT NULL AND phone_number <> ''",
                                                       algorithm: :concurrently, if_not_exists: true
  end
end
