# frozen_string_literal: true

# Unidades (filiais) — a empresa que atende por aqui tem mais de um endereço, e cada
# um abre em horário próprio. Hoje o sistema não tem NENHUMA noção de lugar: não há
# tabela, coluna nem campo de cidade em entidade nenhuma da operação.
#
# A unidade agrupa CAIXAS DE ENTRADA (a linha de WhatsApp daquela filial) e descreve
# como aquele lugar funciona. O horário aqui é INFORMATIVO — quem dispara mensagem de
# ausência continua sendo `inboxes.working_hours`, intocado. Ver o .md da task.
#
# Aditiva e reversível: sem unidade cadastrada, nada muda em lugar nenhum.
class CreateUnits < ActiveRecord::Migration[7.1]
  def change
    criar_unidades
    criar_horarios
    criar_excecoes

    # A caixa pertence a no máximo uma unidade. Nullify: apagar a unidade não pode
    # levar a caixa junto — ela é onde as conversas vivem.
    add_reference :inboxes, :unit, null: true, foreign_key: { on_delete: :nullify }
  end

  private

  def criar_unidades
    create_table :units do |t|
      t.references :account, null: false, foreign_key: true
      t.string  :name, null: false
      t.string  :city
      t.string  :state
      t.string  :address
      t.string  :phone
      # Fuso da unidade: é dele que sai o "aberta agora". Mesmo default de `inboxes`.
      t.string  :timezone, null: false, default: 'UTC'
      t.text    :notes
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :units, [:account_id, :name], unique: true
  end

  # Grade semanal, uma linha por dia — mesmo formato de `working_hours` de propósito,
  # para reaproveitar o editor de horário que já existe no front.
  def criar_horarios
    create_table :unit_working_hours do |t|
      t.references :unit, null: false, foreign_key: { on_delete: :cascade }
      t.integer :day_of_week, null: false
      t.boolean :closed_all_day, null: false, default: false
      t.boolean :open_all_day, null: false, default: false
      t.integer :open_hour
      t.integer :open_minutes
      t.integer :close_hour
      t.integer :close_minutes
      t.timestamps
    end
    add_index :unit_working_hours, [:unit_id, :day_of_week], unique: true
  end

  # Exceção de data: o feriado, que não existe em lugar nenhum do sistema hoje.
  # Ou fecha o dia, ou substitui o horário dele. `annual` cobre feriado de data fixa
  # (25/12) sem recadastro todo ano.
  def criar_excecoes
    create_table :unit_exceptions do |t|
      t.references :unit, null: false, foreign_key: { on_delete: :cascade }
      t.date    :date, null: false
      t.string  :name, null: false
      t.boolean :closed_all_day, null: false, default: true
      t.boolean :annual, null: false, default: false
      t.integer :open_hour
      t.integer :open_minutes
      t.integer :close_hour
      t.integer :close_minutes
      t.timestamps
    end
    add_index :unit_exceptions, [:unit_id, :date], unique: true
  end
end
