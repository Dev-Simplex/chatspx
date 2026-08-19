# frozen_string_literal: true

# Bloco 5.07 (T-C2.0) — PROPAGACAO DO SDK.
#
# O PROBLEMA, MEDIDO: `config/environments/production.rb:24-26` manda
# `Cache-Control: public, max-age=31556952` (um ano) para TUDO que sai de `public/`. O
# `sdk.js` mora num caminho FIXO (`/packs/js/sdk.js` — ver o snippet em
# `Channel::WebWidget#web_widget_script`), sem fingerprint e sem cache-buster no snippet.
#
# A combinacao e a pior possivel: um navegador que baixou o `sdk.js` **nao volta a pedir
# por um ano**. Nao e teoria — nove blocos desta onda mexem no `sdk.js`, e um visitante
# recorrente pode ficar com o arquivo velho por ate 12 meses. Um teaser, uma correcao de
# seguranca ou o coletor de origem simplesmente nao chegam nele.
#
# POR QUE MIDDLEWARE, E NAO CONFIG: `config.public_file_server.headers` e um hash UNICO
# para todos os arquivos — ele nao sabe distinguir caminho. E o header, nesta frota, sai do
# RAILS e nao do nginx (medicao do plano, §A.4.1), entao a correcao pertence aqui e chega a
# todas as VMs pelo deploy, sem depender de mexer em nginx maquina a maquina.
#
# O QUE ELE FAZ: para os caminhos do SDK — e SO para eles — troca o ano por uma janela
# curta com revalidacao. O visitante passa a fazer UMA requisicao condicional por janela;
# como o `ActionDispatch::Static` ja responde `ETag`/`Last-Modified`, a resposta comum e um
# **304 sem corpo**, que custa cabecalho e nao os 39 kB do arquivo.
#
# O QUE ELE NAO FAZ: nao toca em nenhum outro asset. O resto de `public/` continua com o
# ano de cache, que esta certo para caminho com fingerprint — mexer nisso seria trocar um
# defeito por uma conta de banda.
class SdkCachePolicy
  # Caminhos do SDK. E uma lista de caminhos EXATOS, e nao um prefixo `/packs/js/`, de
  # proposito: prefixo pegaria qualquer arquivo futuro que alguem coloque ali e o tiraria do
  # cache longo sem que ninguem tenha decidido isso.
  #
  # `tracking.js` (bloco 5.08) entra pelo MESMO motivo: e artefato do SDK, de caminho fixo,
  # sem fingerprint, buscado em runtime pelo carregador fino. Deixa-lo com o ano de cache
  # recriaria o defeito que este arquivo existe para fechar, so que num arquivo novo.
  SDK_PATHS = ['/packs/js/sdk.js', '/packs/js/tracking.js'].freeze

  # Janela de revalidacao. 5 minutos e o numero que faz o aceite do bloco ser verdadeiro
  # ("uma versao nova chega em MINUTOS a um navegador que ja tinha a antiga") com o menor
  # custo: no pior caso o visitante paga um 304 a cada 5 min de navegacao, e so no primeiro
  # pedido depois de um deploy ele paga o corpo.
  MAX_AGE = 300

  # `must-revalidate` fecha a brecha do cache servir versao vencida quando esta offline ou
  # sob erro de rede; `public` fica porque o arquivo e o mesmo para todo mundo e proxies
  # podem (e devem) guarda-lo.
  CACHE_CONTROL = "public, max-age=#{MAX_AGE}, must-revalidate".freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    return [status, headers, body] unless sdk_request?(env)

    [status, headers.merge('Cache-Control' => CACHE_CONTROL), body]
  end

  private

  # So GET/HEAD: um POST para este caminho nao existe, e reescrever cabecalho de resposta de
  # metodo que nao seja de leitura seria agir fora do que este middleware entende.
  def sdk_request?(env)
    return false unless %w[GET HEAD].include?(env['REQUEST_METHOD'])

    SDK_PATHS.include?(env['PATH_INFO'])
  end
end
