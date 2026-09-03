# frozen_string_literal: true

# Mecanismo de aceite do bloco 2.09 — o zoom devolvido ao visitante.
#
# ACEITE (§2.2): "o `meta viewport` não contém `user-scalable=0` nem
# `maximum-scale`".
#
# Roda SEM Rails e SEM banco, como o spec de `lang` do bloco 1.06: o que se
# verifica é uma linha do ERB, e montar meia aplicação para ler um atributo
# estático só acrescentaria motivos de falhar por fora do que se mede.
#
# A asserção é sobre a AUSÊNCIA de duas diretivas, e por isso ela também prova
# que a linha existe — um arquivo sem `meta viewport` nenhum passaria numa
# busca ingênua por "não contém", e um widget sem viewport declarado é pior
# ainda em celular.
RSpec.describe 'widgets/show.html.erb — o meta viewport' do
  let(:caminho) do
    File.expand_path('../../../app/views/widgets/show.html.erb', __dir__)
  end
  let(:linha_viewport) do
    File.read(caminho).lines.find { |l| l.include?('name="viewport"') }
  end

  it 'declara o viewport — sem ele o celular renderiza em 980 px e encolhe tudo' do
    expect(linha_viewport).not_to be_nil
    expect(linha_viewport).to include('width=device-width')
    expect(linha_viewport).to include('initial-scale=1')
  end

  it 'NÃO trava o zoom: sem user-scalable' do
    expect(linha_viewport).not_to include('user-scalable')
  end

  it 'NÃO limita a ampliação: sem maximum-scale' do
    # SC 1.4.4 (AA) exige 200% de ampliação. `maximum-scale=1` impede, e dentro
    # de um iframe o visitante não tem outra saída.
    expect(linha_viewport).not_to include('maximum-scale')
  end

  it 'e nada no que é RENDERIZADO reintroduz as duas em outro lugar' do
    # Os comentários ERB (`<%# … %>`) saem antes da varredura de propósito: eles
    # não chegam ao HTML, e o comentário desta mudança cita as duas diretivas
    # justamente ao explicar por que elas foram embora. Medir o arquivo cru
    # transformaria a explicação em falha — e o incentivo seria apagar a razão.
    renderizado = File.read(caminho).gsub(/<%#.*?%>/m, '')
    diretivas = renderizado.scan(/user-scalable|maximum-scale/)

    expect(diretivas).to eq([])
  end
end
