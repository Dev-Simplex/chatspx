require 'rails_helper'

# ESTE ARQUIVO FICA VERMELHO DE PROPÓSITO.
#
# A asserção é **"a trava precisa AVALIAR e reconhecer a fonte do código"** — não "a foto
# precisa ser bloqueada". Mandar foto do imóvel que o cliente pediu, ou do imóvel que ele
# clicou no anúncio, é o comportamento certo. O defeito é a ferramenta agir sem olhar de onde
# veio o código: hoje ela acerta por acidente, e acertaria igual com um código inventado.
#
# Fontes que a trava deveria reconhecer (`FONTES_ACEITAVEIS`):
#   - busca desta conversa;
#   - código que o CLIENTE citou (link colado, "Ref: 9412") — ele escolheu aquele imóvel;
#   - código do template da campanha que o cliente clicou — identifica QUAL imóvel interessa.
#
# E o limite do template: ele diz qual imóvel, **nunca** prova preço ou condição comercial.
# "Entrada facilitada" escrita no anúncio não é fato confirmado (§15 da auditoria).
#
# O defeito (§3.7 e §16.1):
#
#   if vistos.any? && !vistos.include?(cod)   # enviar_fotos_imovel_tool.rb
#
# O `vistos.any?` faz a trava só EXISTIR depois que alguma busca registrou código. Conversa sem
# busca nenhuma não é recusada — ela nem é avaliada. E a `enviar_localizacao_imovel` não tem
# trava alguma: não inclui o `ImoveisConhecidos`.
#
# Duas saídas legítimas, as duas fora do escopo de quem só quer verde:
#   1. a trava passa a avaliar sempre e a aceitar as três fontes — e este teste passa; ou
#   2. decide-se conscientemente manter como está, escreve-se a decisão no doc 06 e apaga-se
#      este arquivo.
# Reescrever a asserção para caber no comportamento de hoje não é nenhuma das duas.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ação sobre imóvel com a trava não avaliada' do
  def fixtures
    Rails.root.glob('spec/fixtures/captain/harness/*.yml').map do |caminho|
      [caminho.basename('.yml').to_s, YAML.safe_load_file(caminho)]
    end
  end

  # As ações que a fixture registra como executadas antes da primeira busca. O gravador só
  # anota este caso porque é o único decidível pelo trace: depois que existe busca, um código
  # ausente do `result_preview` ainda pode ser o ImoCodigo que a trava conhece pelo mapa de urls.
  def acoes
    fixtures.flat_map do |id, dados|
      Array(dados['acoes_sem_trava']).map { |a| a.merge('fixture' => id) }
    end
  end

  it 'toda ação sobre imóvel passa por uma trava que avalia a fonte do código' do
    agiram = acoes.select { |a| a['observado'] == 'agiu_sem_avaliar' }
    relato = agiram.map do |a|
      "#{a['fixture']}: #{a['tool']}(#{a['codigo']}) — fonte #{a['fonte_do_codigo']} " \
        "(aceitável: #{a['fonte_aceitavel']}), esperado #{a['esperado']}"
    end

    expect(agiram).to be_empty,
                      "#{agiram.size} ação(ões) agiram sem a trava avaliar a fonte:\n  " \
                      "#{relato.join("\n  ")}\n" \
                      "\n#{Spx::Harness::FixtureExportada::PORQUE_FAIL_OPEN}"
  end

  # O ponto que separa esta asserção de "bloquear a foto": nas três ações registradas, a fonte
  # do código ERA aceitável. O cliente colou o link, ou clicou o anúncio. Se alguma deixasse de
  # ser, a expectativa daquela linha viraria `bloquear` sozinha — e aí o defeito seria outro,
  # pior, que este exemplo faria aparecer.
  it 'as ações registradas hoje têm fonte aceitável — o defeito é não avaliar, não o envio' do
    expect(acoes).not_to be_empty
    expect(acoes.pluck('fonte_do_codigo').uniq)
      .to all(be_in(Spx::Harness::FixtureExportada::FONTES_ACEITAVEIS))
    expect(acoes.pluck('esperado').uniq).to eq(['reconhecer_fonte'])
  end

  # Este passa hoje e precisa continuar passando: quando a trava É avaliada, ela recusa. O
  # defeito é a condição de entrada, não a decisão.
  it 'quando a trava é avaliada, ela recusa código que a busca não devolveu' do
    recusas = fixtures.flat_map do |_id, dados|
      Array(dados['chamadas']).select do |c|
        c['tool'] == 'enviar_fotos_imovel' && c['resultado'].to_s.include?('não apareceu na busca')
      end
    end

    expect(recusas).not_to be_empty
    expect(recusas).to all(include('status' => 'ok'))
  end
end
# rubocop:enable RSpec/DescribeClass
