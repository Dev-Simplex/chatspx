require 'rails_helper'
require Rails.root.join('db/migrate/20260916220000_fk_que_travam_exclusao')

# Guarda o estado final das FKs que travavam exclusao (T07). Os casos de ponta a ponta estao em
# spec/models/contact_spec.rb e spec/jobs/delete_object_job_spec.rb.
RSpec.describe FkQueTravamExclusao do
  let(:conn) { ActiveRecord::Base.connection }

  it 'leaves every targeted foreign key with the expected ON DELETE' do
    esperado = (described_class::CASCADE + described_class::REAFIRMADAS).map { |alvo| [*alvo, :cascade] } +
               described_class::NULLIFY.map { |alvo| [*alvo, :nullify] }

    divergentes = esperado.filter_map do |tabela, coluna, pai, acao|
      fk = conn.foreign_keys(tabela).find { |f| f.column == coluna && f.to_table == pai }
      next if fk.nil? # a migration pula FK que nao existe neste banco (ex.: scheduled_messages.account_id)

      "#{tabela}.#{coluna} -> #{pai}: #{fk.on_delete.inspect}" unless fk.on_delete == acao
    end

    expect(divergentes).to be_empty
  end
end
