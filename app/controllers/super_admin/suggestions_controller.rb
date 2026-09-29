# Painel da Simplex: le as sugestoes de TODAS as contas e move o status. O usuario ve o status em
# "Minhas sugestoes" — por isso `status` e o unico campo editavel (ver SuggestionDashboard).
class SuperAdmin::SuggestionsController < SuperAdmin::ApplicationController
  def scoped_resource
    resource_class.includes(:account).recentes
  end
end
