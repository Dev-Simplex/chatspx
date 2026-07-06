# frozen_string_literal: true

# Faz um Flow (e um conjunto de condições de um nó) "parecer" um AutomationRule para o
# AutomationRules::ConditionsFilterService — assim reusamos o motor de condição inteiro
# (a query SQL, os operadores, custom attributes) sem reescrever nada. O serviço só toca
# `conditions`, `id`, `account` e `authorization_error!`
# (conditions_filter_service.rb:29/41/48/206, condition_validation_service.rb:7/17/61).
#
# NÃO incluímos o concern Reauthorizable de propósito: o `authorization_error!` dele
# depende de `self.class.table_name` e `inbox`, que um objeto efêmero não tem — chamá-lo
# levantaria NoMethodError. Definimos um no-op que apenas registra.
class Flows::RuleAdapter
  attr_reader :conditions, :id, :account

  def initialize(conditions:, flow:)
    @conditions = conditions || []
    @id = flow.id
    @account = flow.account
  end

  # Chamado por ConditionsFilterService#rule_valid? quando as condições são inválidas
  # (conditions_filter_service.rb:48). No AutomationRule isto conta erros e desativa a
  # regra; num Flow efêmero apenas registramos — o #perform já retorna false, então o
  # ramo simplesmente não passa (sem derrubar o fluxo).
  def authorization_error!
    Rails.logger.warn("Flows::RuleAdapter: invalid conditions for flow ##{@id}")
  end
end
