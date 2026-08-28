# frozen_string_literal: true

# Unidades (filiais) — CRUD do cadastro, do horário semanal e das exceções de data.
# Os três vêm e vão juntos: a tela edita a unidade inteira num request só, via
# accepts_nested_attributes_for. São poucos registros (7 dias + punhado de feriados).
#
# Ligar caixas à unidade acontece por `inbox_ids`, não por nested attributes: a caixa
# é dona da própria vida e só empresta a coluna `unit_id`.
class Api::V1::Accounts::UnitsController < Api::V1::Accounts::BaseController
  before_action :unit, except: [:index, :create]
  before_action :check_authorization

  def index
    @units = policy_scope(Unit).includes(:working_hours, :exceptions, :inboxes).order(:name)
  end

  def show; end

  # As três gravações vão juntas ou não vão: as exceções são substituídas em bloco
  # (destroy_all + create!), e sem a transação um feriado inválido apagava os antigos
  # e ainda devolvia 422 — o usuário via o erro E perdia o que tinha. No create, sem
  # ela, a unidade ficava gravada pela metade depois de a tela mostrar a falha.
  def create
    ActiveRecord::Base.transaction do
      @unit = Current.account.units.create!(unit_params)
      sincronizar_caixas
      sincronizar_excecoes
    end
    render :show, status: :created
  end

  def update
    ActiveRecord::Base.transaction do
      @unit.update!(unit_params)
      sincronizar_caixas
      sincronizar_excecoes
    end
    render :show
  end

  def destroy
    @unit.destroy!
    head :ok
  end

  private

  def unit
    @unit ||= policy_scope(Unit).find(params[:id])
  end

  def unit_params
    params.require(:unit).permit(
      :name, :city, :state, :address, :phone, :timezone, :notes, :active,
      working_hours_attributes: [:id, :day_of_week, :closed_all_day, :open_all_day,
                                 :open_hour, :open_minutes, :close_hour, :close_minutes,
                                 :break_start_hour, :break_start_minutes,
                                 :break_end_hour, :break_end_minutes]
    )
  end

  # As regras de agenda (feriado, evento, temporada) e a repetição de cada uma. Array
  # em strong params exige a chave declarada como lista: `weekdays: []`.
  def excecoes_params
    params.require(:unit).permit(
      exceptions: [:starts_on, :ends_on, :name, :category, :closed_all_day,
                   :frequency, :repeat_interval, :until_date,
                   :open_hour, :open_minutes, :close_hour, :close_minutes,
                   { weekdays: [], week_positions: [], month_days: [] }]
    )[:exceptions]
  end

  # Chave ausente = não mexe. Só reatribui caixas DESTA conta; id de fora é ignorado
  # em silêncio, nunca vira vínculo.
  def sincronizar_caixas
    return if params[:unit][:inbox_ids].nil?

    desejadas = Current.account.inboxes.where(id: params[:unit][:inbox_ids]).pluck(:id)
    Current.account.inboxes.where(unit_id: @unit.id).where.not(id: desejadas).update_all(unit_id: nil) # rubocop:disable Rails/SkipsModelValidations
    Current.account.inboxes.where(id: desejadas).update_all(unit_id: @unit.id) # rubocop:disable Rails/SkipsModelValidations
    @unit.association(:inboxes).reset
  end

  # Substitui o conjunto inteiro. Chave ausente = não mexe; lista vazia = apagou todas.
  # Vale porque exceção não é referenciada por ninguém — recriar não quebra nada.
  def sincronizar_excecoes
    desejadas = excecoes_params
    return if desejadas.nil?

    @unit.exceptions.destroy_all
    desejadas.each { |atributos| @unit.exceptions.create!(atributos) }
    @unit.association(:exceptions).reset
  end

  def check_authorization
    authorize(@unit || Unit.new(account: Current.account))
  end
end
