# frozen_string_literal: true

# GET /api/v1/accounts/:account_id/contact_names?phones[]=5566996571379&phones[]=...
# Nome salvo do dono de cada numero (Contacts::SavedNames). A tela pede em lote os numeros que esta mostrando.
class Api::V1::Accounts::ContactNamesController < Api::V1::Accounts::BaseController
  MAX_PHONES = 200

  def show
    render json: { contacts: Contacts::SavedNames.call(Current.account, Array(params[:phones]).first(MAX_PHONES)) }
  end
end
