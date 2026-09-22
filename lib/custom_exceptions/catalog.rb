# frozen_string_literal: true

# Erros NOMEADOS do catálogo (C9). Nomeados porque a C8 precisa distinguir "configure o catálogo da
# conta" de "espere a sincronização" para dizer ao atendente o que fazer — um RuntimeError genérico
# chegaria na tela como "erro inesperado".
module CustomExceptions::Catalog
  # Cota da Meta (`200 + 40 × catálogos` por hora) estourada. Quem pega este erro PARA a passada e
  # reagenda: repetir na hora só queima o que sobrou da cota.
  class MetaRateLimited < CustomExceptions::Base
    def message
      I18n.t 'errors.catalog.meta_rate_limited'
    end
  end

  # A conta não tem catálogo na Meta (`settings.meta_catalog_id`). Sem ele não existe `catalog_id`
  # para pôr no payload — é configuração pendente, não defeito.
  class CatalogNotConfigured < CustomExceptions::Base
    def message
      I18n.t 'errors.catalog.not_configured'
    end
  end

  # O estado "ainda não sincronizado": produto sem SKU ou sem `meta_product_id` não existe no
  # catálogo da Meta, e mandá-lo assim entrega ao cliente uma mensagem de produto vazia.
  class ProductNotSynced < CustomExceptions::Base
    def message
      I18n.t 'errors.catalog.product_not_synced', product: @data[:product]
    end
  end

  # Caixa que não é `whatsapp_cloud` (a WAHA não tem catálogo — ver C10, bloqueada por decisão de
  # produto).
  class ChannelNotSupported < CustomExceptions::Base
    def message
      I18n.t 'errors.catalog.channel_not_supported'
    end
  end

  # Teto de 30 itens do `product_list` da Meta. Erro claro em vez de truncar calado: cortar a lista
  # mandaria ao cliente menos do que o atendente escolheu, sem ninguém saber.
  class TooManyProducts < CustomExceptions::Base
    def message
      I18n.t 'errors.catalog.too_many_products', limit: @data[:limit], count: @data[:count]
    end
  end
end
