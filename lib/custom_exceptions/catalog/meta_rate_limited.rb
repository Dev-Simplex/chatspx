# frozen_string_literal: true

# Cota da Meta (`200 + 40 × catálogos` por hora) estourada, no espelho do catálogo (C9). Quem pega
# este erro PARA a passada e reagenda: repetir na hora só queima o que sobrou da cota.
class CustomExceptions::Catalog::MetaRateLimited < CustomExceptions::Base
  def message
    I18n.t 'errors.catalog.meta_rate_limited'
  end
end
