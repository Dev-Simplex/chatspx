# Bloco 4.17 — origem e confianca de uma definicao de atributo.
#
# ADITIVA de proposito, e as duas colunas nascem SEM default e SEM null: false.
#
# Nao e preciosismo: esta migration roda sobre tabela que ja tem dado em toda VM da frota,
# e restricao acrescentada sobre linha existente e o tipo de coisa que passa no banco de
# teste vazio e falha na producao. Sem default nao ha reescrita de tabela; sem NOT NULL nao
# ha linha antiga que viole a regra no instante do ALTER.
#
# `nil` tem significado nas duas (regra A4, a mesma das chaves de widget do 3.01):
#   origin nil                    definicao anterior a esta coluna — nao se sabe quem criou,
#                                 e inventar "agent" seria afirmar o que nao se mediu;
#   requires_verified_origin nil  nao exige — que e exatamente o comportamento de hoje.
# Por isso nao ha backfill.
class AddOriginToCustomAttributeDefinitions < ActiveRecord::Migration[7.1]
  def change
    add_column :custom_attribute_definitions, :origin, :string
    add_column :custom_attribute_definitions, :requires_verified_origin, :boolean

    # Parcial: so as definicoes protegidas entram. Elas sao a minoria, e a consulta que
    # importa no caminho quente e exatamente "quais chaves desta conta sao protegidas".
    add_index :custom_attribute_definitions, %i[account_id attribute_model],
              where: 'requires_verified_origin IS TRUE',
              name: 'index_cad_on_account_and_model_when_protected'
  end
end
