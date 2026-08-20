# frozen_string_literal: true

require Rails.root.join('lib/sdk_cache_policy')

# Bloco 5.07 — o middleware precisa correr DEPOIS do `ActionDispatch::Static` ter montado a
# resposta do arquivo (ele e quem escreve o `Cache-Control` de um ano vindo de
# `config.public_file_server.headers`), e a pilha do Rack executa de fora para dentro: quem
# esta ANTES na lista embrulha quem vem depois, e por isso ve a resposta ja pronta na volta.
#
# `insert_before 0` (o mesmo lugar do Rack::Cors) garante que ele embrulhe a pilha inteira,
# inclusive o Static. Sem isso, a reescrita aconteceria antes de o header existir e nao
# faria nada — falha silenciosa, do tipo que fica verde no teste errado.
Rails.application.config.middleware.insert_before 0, SdkCachePolicy
