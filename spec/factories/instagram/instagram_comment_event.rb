# Espelha o payload REAL capturado na .232 em 24/08/2026 (conta da BigStore). Não é payload
# inventado a partir da documentação: os nomes de campo, o aninhamento e a ausência de timestamp
# dentro de `value` são o que a Meta manda de fato.
FactoryBot.define do
  factory :instagram_comment_event, class: Hash do
    transient do
      ig_account_id { '17841468839878751' }
      comment_id { '18403150897094528' }
      author_id { '927295776379836' }
      author_username { 'daynomergpescaria' }
      text { 'No domingo que horas abre a loja' }
      media_id { '18103036610158975' }
      media_product_type { 'REELS' }
      field { 'comments' }
    end

    entry do
      [
        {
          'id': ig_account_id,
          'time': 1_787_522_739,
          'changes': [
            {
              'value': {
                'from': { 'id': author_id, 'username': author_username },
                'media': { 'id': media_id, 'media_product_type': media_product_type },
                'id': comment_id,
                'text': text
              },
              'field': field
            }
          ]
        }
      ]
    end

    initialize_with { attributes }
  end
end
