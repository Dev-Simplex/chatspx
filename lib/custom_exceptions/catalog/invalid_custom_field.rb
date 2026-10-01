# frozen_string_literal: true

# Valor de campo personalizado do catálogo que não converte para o tipo do campo. Diz QUAL campo:
# o formulário tem vários, e "valor inválido" sem nome manda o usuário caçar.
class CustomExceptions::Catalog::InvalidCustomField < CustomExceptions::Base
  def message
    I18n.t('errors.catalog.invalid_custom_field', field: @data[:field])
  end

  def http_status
    422
  end
end
