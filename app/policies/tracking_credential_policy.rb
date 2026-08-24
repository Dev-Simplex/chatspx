class TrackingCredentialPolicy < ApplicationPolicy
  # Segredo de anuncio e assunto de administrador: um agente comum nao precisa nem ver que existe.
  def show?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def verify?
    @account_user.administrator?
  end
end
