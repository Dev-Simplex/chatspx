json.id article.id
json.title article.title
json.locale article.locale
json.content article.content
json.slug article.slug
json.portal_slug article.portal.slug if article.portal.present?
json.account_id article.account_id
json.category_name article.category&.name
json.status article.status
json.updated_at article.updated_at.to_i
