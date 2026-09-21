require 'rails_helper'

# ESTE ARQUIVO FICA VERMELHO DE PROPÓSITO.
#
# Ele afirma o comportamento CERTO — ação sobre imóvel só sai depois que uma busca desta
# conversa devolveu aquele código — e hoje a produção não cumpre. Não é teste quebrado: é a
# asserção do defeito, aberta, para que o verde do resto da suíte não passe a impressão de que
# está tudo coberto.
#
# O defeito (§3.7 da auditoria): a trava anti-alucinação é
#
#   if vistos.any? && !vistos.include?(cod)   # enviar_fotos_imovel_tool.rb
#
# O `vistos.any?` faz a trava existir SÓ depois que alguma busca registrou código. Conversa sem
# busca nenhuma não é recusada — ela nem é avaliada. Fail-open por construção.
#
# Duas saídas legítimas para este arquivo, as duas fora do escopo de quem só quer verde:
#   1. fechar a trava (exigir busca, e então este teste passa); ou
#   2. decidir que ela fica fail-open, escrever a decisão no doc 06 e apagar este arquivo.
# Reescrever a asserção para caber no comportamento de hoje não é nenhuma das duas.
# O sujeito aqui não é uma classe: é o CORPUS de fixtures gravado no repositório. Quem quebra
# este exemplo é a produção, não um objeto.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ação sobre imóvel sem busca na conversa' do
  def fixtures
    Rails.root.glob('spec/fixtures/captain/harness/*.yml').map do |caminho|
      [caminho.basename('.yml').to_s, YAML.safe_load_file(caminho)]
    end
  end

  # Os envios que a fixture registra como executados antes da primeira busca. O gravador só
  # anota este caso porque é o único decidível pelo trace: depois que existe busca, um código
  # ausente do `result_preview` ainda pode ser o ImoCodigo que a trava conhece pelo mapa de urls.
  def envios_vermelhos
    fixtures.flat_map do |id, dados|
      Array(dados['envios_sem_busca']).select { |e| e['observado'] == 'enviado' }
                                      .map { |e| e.merge('fixture' => id) }
    end
  end

  it 'nenhuma ação sobre imóvel é executada antes de a busca devolver aquele código' do
    relato = envios_vermelhos.map do |e|
      "#{e['fixture']}: #{e['tool']}(#{e['codigo']}) em #{e['em']} — código veio de #{e['codigo_veio_de']}"
    end

    expect(envios_vermelhos).to be_empty,
                                "#{envios_vermelhos.size} ação(ões) saíram com a trava não avaliada:\n  " \
                                "#{relato.join("\n  ")}\n" \
                                "\n#{Spx::Harness::FixtureExportada::PORQUE_FAIL_OPEN}"
  end

  # Este passa hoje e precisa continuar passando: quando a trava É avaliada, ela recusa. O
  # defeito é a condição de entrada, não a decisão.
  it 'quando a trava é avaliada, ela recusa código que a busca não devolveu' do
    recusas = fixtures.flat_map do |_id, dados|
      Array(dados['chamadas']).select do |c|
        c['tool'] == 'enviar_fotos_imovel' && c['resultado'].to_s.include?('não apareceu na busca')
      end
    end

    expect(recusas).to all(include('status' => 'ok'))
    expect(recusas).not_to be_empty
  end
end
# rubocop:enable RSpec/DescribeClass
