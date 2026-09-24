# frozen_string_literal: true

# Erros NOMEADOS do espelho do catálogo na Meta (C9).
module CustomExceptions::Catalog
  # Cota da Meta (`200 + 40 × catálogos` por hora) estourada. Quem pega este erro PARA a passada e
  # reagenda: repetir na hora só queima o que sobrou da cota.
  class MetaRateLimited < CustomExceptions::Base
    def message
      I18n.t 'errors.catalog.meta_rate_limited'
    end
  end
end
