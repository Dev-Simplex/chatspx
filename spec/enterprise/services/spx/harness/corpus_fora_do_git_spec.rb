require 'rails_helper'

# O corpus local guarda a fala PSEUDONIMIZADA, que por decisão de 20/09 não entra no git nem
# assim. Confiar no `.gitignore` por leitura é suposição; aqui se pergunta ao próprio git.
#
# `git check-ignore` devolve 0 quando o caminho está ignorado e 1 quando não está. Se alguém
# mexer no .gitignore e tirar o `/tmp/*`, este exemplo cai antes de o corpus vazar.
RSpec.describe 'corpus do harness fora do versionado', type: :model do
  def ignorado?(caminho)
    Dir.chdir(Rails.root) { system('git', 'check-ignore', '-q', caminho, out: File::NULL, err: File::NULL) }
  end

  # Pergunta ao próprio git se ele consegue operar aqui. Num worktree montado em container o
  # `.git` é um ARQUIVO apontando para fora do mount, então o git falha — e um exemplo que
  # depende dele precisa pular, não mentir que passou.
  before do
    ok = Dir.chdir(Rails.root) { system('git', 'rev-parse', '--is-inside-work-tree', out: File::NULL, err: File::NULL) }
    skip('git indisponível neste ambiente (worktree fora do mount)') unless ok
  end

  it 'ignora o diretório do corpus' do
    expect(ignorado?('tmp/harness-corpus/exemplo.yml')).to be(true)
  end

  it 'ignora qualquer arquivo dentro dele, em qualquer profundidade' do
    expect(ignorado?('tmp/harness-corpus/tozi/41803.yml')).to be(true)
  end

  # Controle: se o check-ignore respondesse "sim" para tudo, o exemplo acima não provaria nada.
  it 'NÃO ignora o diretório das fixtures versionadas' do
    expect(ignorado?('spec/fixtures/captain/harness/exemplo.yml')).to be(false)
  end

  # A trava só vale se for aplicada. Varre o que está versionado hoje.
  it 'não tem vazamento nas fixtures já versionadas' do
    Dir[Rails.root.join('spec/fixtures/captain/harness/*.yml')].each do |arquivo|
      achados = Spx::Harness::Vazamento.varrer(File.read(arquivo))

      expect(achados).to be_empty, "#{File.basename(arquivo)}: #{achados.join(', ')}"
    end
  end
end
