# O limite da rede não é só o HTTP: é o DNS também.
#
# O Captain::Tools::HttpTool resolve o hostname ANTES de montar a requisição, para barrar SSRF
# (`check_private_ip!` -> `Resolv.getaddress`). Isso é uma chamada de rede de verdade, e ela
# acontece mesmo quando a requisição seguinte está stubada pelo WebMock. Consequência prática:
# num cenário de harness com host fictício `.invalid`, o DNS falha primeiro e TODA falha vira
# "a requisição não chegou a ser enviada" — que é justamente a única classificação que afirma
# com segurança que a ação não aconteceu. O cenário não testaria nada do que pretende.
#
# `rede_falsa` fecha esse limite no mesmo lugar em que o WebMock fecha o HTTP: resolve o host
# fictício para um IP PÚBLICO fixo, para que o guard de SSRF passe e o caminho real da tool —
# timeout, 4xx, 5xx, corpo ilegível — seja exercitado de verdade.
#
# 203.0.113.0/24 é a TEST-NET-3 da RFC 5737: reservada para documentação, nunca roteável, e
# fora de qualquer faixa privada. Um IP privado aqui faria o guard barrar e o cenário voltaria
# a testar o guard em vez do que ele quer testar.
module HarnessRedeFalsa
  IP_DE_DOCUMENTACAO = '203.0.113.7'.freeze

  def rede_falsa(*hosts)
    allow(Resolv).to receive(:getaddress) do |nome|
      raise Resolv::ResolvError, "não resolvido no harness: #{nome}" unless hosts.include?(nome)

      IP_DE_DOCUMENTACAO
    end
  end
end

RSpec.configure do |config|
  config.include HarnessRedeFalsa
end
