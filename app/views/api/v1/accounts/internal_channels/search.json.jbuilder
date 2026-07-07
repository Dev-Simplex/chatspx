# frozen_string_literal: true

json.array! @messages, partial: 'api/v1/accounts/internal_channels/search_result', as: :message
