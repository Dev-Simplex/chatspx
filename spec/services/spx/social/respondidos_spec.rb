require 'rails_helper'

# A heurística que responde "o que falta responder?". Ela é inferência: o webhook do Instagram
# não traz `parent_id`, e o que liga a resposta da conta a alguém é o `@` no começo do texto —
# convenção observada em todas as respostas medidas na conta da BigStore em 24/08.
RSpec.describe Spx::Social::Respondidos do
  let(:account) { create(:account) }

  def comentario(atributos)
    build(:social_comentario, { account: account, publicacao_external_id: 'pub-1' }.merge(atributos))
  end

  it 'marca como respondido quem a conta mencionou no começo da resposta' do
    cliente = comentario(autor_username: 'vanderlea__meregildo')
    resposta = comentario(proprio: true, texto: '@vanderlea__meregildo oie, bom dia 🌼')

    respondidos = described_class.new([cliente, resposta])

    expect(respondidos.respondido?(cliente)).to be true
  end

  it 'não marca quem ninguém mencionou' do
    cliente = comentario(autor_username: 'nilgloria')
    resposta = comentario(proprio: true, texto: '@outra_pessoa oie')

    respondidos = described_class.new([cliente, resposta])

    expect(respondidos.respondido?(cliente)).to be false
  end

  it 'ignora diferença de caixa no @' do
    cliente = comentario(autor_username: 'Cauani_Gomes')
    resposta = comentario(proprio: true, texto: '@cauani_gomes oie, bom dia 😃')

    expect(described_class.new([cliente, resposta]).respondido?(cliente)).to be true
  end

  # Menção no meio da frase é citação, não endereçamento. Tratá-la como resposta marcaria como
  # atendida gente que ninguém respondeu — que é o erro caro nesta tela.
  it 'não conta menção no meio do texto' do
    cliente = comentario(autor_username: 'fulano')
    resposta = comentario(proprio: true, texto: 'Como a @fulano falou, temos sim')

    expect(described_class.new([cliente, resposta]).respondido?(cliente)).to be false
  end

  it 'conta mais de um @ quando a resposta endereça duas pessoas' do
    um = comentario(autor_username: 'ana')
    outro = comentario(autor_username: 'bia')
    resposta = comentario(proprio: true, texto: '@ana @bia oie, em todas as unidades')

    respondidos = described_class.new([um, outro, resposta])

    expect(respondidos.respondido?(um)).to be true
    expect(respondidos.respondido?(outro)).to be true
  end

  # A mesma pessoa comentando em duas publicações: responder numa não responde a outra.
  it 'não atravessa publicações' do
    aqui = comentario(autor_username: 'ana', publicacao_external_id: 'pub-1')
    la = comentario(autor_username: 'ana', publicacao_external_id: 'pub-2')
    resposta = comentario(proprio: true, texto: '@ana oie', publicacao_external_id: 'pub-1')

    respondidos = described_class.new([aqui, la, resposta])

    expect(respondidos.respondido?(aqui)).to be true
    expect(respondidos.respondido?(la)).to be false
  end

  it 'nunca marca a própria resposta da conta como respondida' do
    resposta = comentario(proprio: true, texto: '@bigstoreutilidades oie')

    expect(described_class.new([resposta]).respondido?(resposta)).to be false
  end

  # Comentário capturado antes de o escopo de autor existir (18/08) vem sem username.
  it 'trata comentário sem autor como não respondido, em vez de estourar' do
    sem_autor = comentario(autor_username: nil)
    resposta = comentario(proprio: true, texto: '@alguem oie')

    expect(described_class.new([sem_autor, resposta]).respondido?(sem_autor)).to be false
  end
end
