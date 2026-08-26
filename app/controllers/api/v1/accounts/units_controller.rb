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

  def create
    @unit = Current.account.units.create!(unit_params)
    sincronizar_caixas
    render :show, status: :created
  end

  def update
    @unit.update!(unit_params)
    sincronizar_caixas
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
                                 :open_hour, :open_minutes, :close_hour, :close_minutes],
      exceptions_attributes: [:id, :date, :name, :closed_all_day, :annual,
                              :open_hour, :open_minutes, :close_hour, :close_minutes, :_destroy]
    )
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

  def check_authorization
    authorize(@unit || Unit.new(account: Current.account))
  end
end
