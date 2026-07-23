class ConversationTakeoverRequestPolicy < ApplicationPolicy
  # Qualquer membro da conta vê a PRÓPRIA lista — o index filtra por
  # owner_id/requester_id, então é seguro por construção.
  def index?
    true
  end

  # Admin não pede: ele já atribui direto (o gate não o barra), então um pedido
  # dele seria teatro.
  def create?
    !@account_user.administrator?
  end

  # D3: responde quem é dono do pedido — ou admin (que força).
  def approve?
    owner_or_admin?
  end

  def deny?
    owner_or_admin?
  end

  # Desistir é do solicitante (ou admin, p/ limpar).
  def cancel?
    @record.requester_id == @user.id || @account_user.administrator?
  end

  private

  def owner_or_admin?
    @record.owner_id == @user.id || @account_user.administrator?
  end
end
