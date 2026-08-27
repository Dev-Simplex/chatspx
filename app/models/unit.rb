# frozen_string_literal: true

# Unidade (filial) — um endereço da empresa, com horário próprio.
#
# Agrupa CAIXAS DE ENTRADA: a linha de WhatsApp daquela filial pertence a ela. É por
# isso que a unidade não precisa aparecer na conversa: a conversa herda a unidade pela
# caixa em que entrou, sem coluna nova em `conversations`.
#
# O horário aqui é INFORMATIVO — serve para o atendente responder "vocês abrem sábado?".
# Quem dispara mensagem de ausência, move o widget e alimenta a métrica de horário
# comercial continua sendo `inboxes.working_hours`, que este modelo NÃO toca.
class Unit < ApplicationRecord
  DIAS_DA_SEMANA = (0..6).to_a.freeze

  belongs_to :account
  has_many :working_hours, class_name: 'UnitWorkingHour', dependent: :destroy
  has_many :exceptions, class_name: 'UnitException', dependent: :destroy
  # Nullify no banco (a FK cuida): apagar a unidade não pode levar a caixa junto.
  has_many :inboxes, dependent: :nullify

  # Só o horário é nested: são sempre os mesmos 7 dias, atualizados por id. As
  # exceções o controller substitui em bloco — são poucas, sempre editadas como lista,
  # e assim a tela não precisa carregar `_destroy` de um lado para o outro.
  accepts_nested_attributes_for :working_hours

  validates :name, presence: true, uniqueness: { scope: :account_id, case_sensitive: false }
  validates :timezone, presence: true
  validate :timezone_deve_existir

  after_create :criar_grade_padrao

  private

  def timezone_deve_existir
    return if timezone.blank? || TZInfo::Timezone.all_identifiers.include?(timezone)

    errors.add(:timezone, I18n.t('errors.validations.invalid'))
  end

  # Nasce com a semana inteira, como a caixa de entrada faz em OutOfOffisable: seg-sex
  # 08:00-18:00, sábado e domingo fechados. Sem isso a tela abriria vazia e quem
  # cadastra teria que criar sete linhas na mão.
  #
  # Quem já mandou a grade (a tela sempre manda, também ao criar) não recebe a padrão
  # por cima: as sete linhas do nested attributes já estão gravadas quando este
  # callback roda, e criar de novo esbarra no índice único (unidade, dia).
  def criar_grade_padrao
    return if working_hours.any?

    DIAS_DA_SEMANA.each do |dia|
      fim_de_semana = [0, 6].include?(dia)
      working_hours.create!(
        day_of_week: dia,
        closed_all_day: fim_de_semana,
        open_hour: fim_de_semana ? nil : 8,
        open_minutes: fim_de_semana ? nil : 0,
        close_hour: fim_de_semana ? nil : 18,
        close_minutes: fim_de_semana ? nil : 0
      )
    end
  end
end
