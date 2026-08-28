# Mesma regra do cofre (`TrackingCredentialPolicy`): o log de rastreio mostra o que a conta
# manda para os destinos de anuncio, e isso e assunto de administrador. Um agente comum nao
# precisa nem saber que a integracao existe.
class TrackingDeliveryPolicy < ApplicationPolicy
  def index?
    @account_user.administrator?
  end

  def test?
    @account_user.administrator?
  end
end
