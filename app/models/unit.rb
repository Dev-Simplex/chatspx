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
  include UnitAtendimento

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
  # Coordenada é opcional — unidade sem pin é ausência legítima, não erro. Mas fora de faixa é
  # erro: latitude 100 não existe, e um ponto inválido some no mapa em vez de avisar.
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 },
                       allow_nil: true
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 },
                        allow_nil: true
  validate :timezone_deve_existir

  before_save :arrumar_contatos, :arrumar_links
  after_create :criar_grade_padrao

  private

  # A tela adiciona a linha vazia antes de preencher, e quem desiste deixa ela para trás: linha sem
  # número não vira registro. O `phone` acompanha o primeiro contato porque é ele que a lista de
  # unidades e a API mostram.
  def arrumar_contatos
    self.contacts = Array(contacts).filter_map do |contato|
      next if contato['phone'].blank?

      { 'label' => contato['label'].to_s.strip, 'phone' => contato['phone'].strip }
    end
    # Quem manda só o `phone` — a API de antes da lista — não pode perder o número: ele vira o
    # primeiro contato. Quem apaga a lista inteira na tela não recebe o contato de volta, porque
    # ali o `phone` não mudou; é o que separa "não conhece a lista" de "apagou de propósito".
    self.contacts = [{ 'label' => '', 'phone' => phone.strip }] if contacts.empty? && phone.present? && phone_changed?
    self.phone = contacts.first&.fetch('phone', nil)
  end

  def arrumar_links
    self.social_links = Array(social_links).filter_map do |link|
      next if link['url'].blank?

      { 'network' => link['network'].to_s, 'url' => com_esquema(link['url'].strip) }
    end
  end

  # Quem copia da barra do navegador traz o https; quem digita à mão escreve "instagram.com/x", e
  # sem esquema o navegador trata como caminho relativo do painel.
  def com_esquema(url)
    url.match?(%r{\Ahttps?://}) ? url : "https://#{url}"
  end

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
