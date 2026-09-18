# frozen_string_literal: true

# Miniatura pedida antes de o arquivo chegar ao disco: o Message dispara `message.created` no
# after_create_commit e o upload do anexo so acontece no after_commit do Attachment, que roda depois.
# O navegador recebe a mensagem pelo socket, pede a representacao e o Rails respondia 500 — a issue
# mais frequente do GlitchTip (201 eventos na .229, 132 na Tozi), e em 82% dos casos o blob existia
# segundos depois. 404 com `no-store`: o front tenta de novo (useLoadWithRetry / useImageListRetry) e
# nada fica guardado no cache do navegador. Um placeholder 200 seria pior: pararia a retentativa e, com
# o cache de um dia do nginx, a foto certa nao apareceria mais.
Rails.application.config.to_prepare do
  ActiveStorage::BaseController.class_eval do
    rescue_from ActiveStorage::FileNotFoundError do
      response.headers['Cache-Control'] = 'no-store'
      head :not_found
    end
  end
end
