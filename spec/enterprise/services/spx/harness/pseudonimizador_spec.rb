require 'rails_helper'

RSpec.describe Spx::Harness::Pseudonimizador do
  subject(:p) { described_class.new(semente: 'fixture-1') }

  describe 'o contrato com a trava' do
    # É ESTE o exemplo que importa: o que sai daqui tem que passar no Vazamento. Se um dia
    # deixar de passar, o gravador para de gravar — que é o comportamento certo.
    it 'produz texto que o Vazamento aceita' do
      sujo = 'Oi, sou a Ana Paula, meu zap é (66) 99958-6623 e o e-mail ana@gmail.com. ' \
             'Moro na Av. das Figueiras, 1646. senha: batatinha123'

      limpo = p.aplicar(sujo, nomes: ['Ana Paula'])

      expect(Spx::Harness::Vazamento.varrer(limpo)).to be_empty
    end
  end

  describe 'estabilidade' do
    # A conversa precisa continuar fazendo sentido: "o número que você mandou" tem que ser o
    # mesmo número duas linhas depois. Aleatório quebraria a coerência da fixture.
    it 'troca o mesmo valor pelo mesmo pseudônimo dentro da fixture' do
      texto = p.aplicar('liga no 66 99958-6623 ou manda no 66 99958-6623')
      numeros = texto.scan(/\(66\) 90000-\d{4}/)

      expect(numeros.uniq.size).to eq(1)
      expect(numeros.size).to eq(2)
    end

    it 'dá pseudônimos diferentes para fixtures diferentes' do
      outro = described_class.new(semente: 'fixture-2')

      expect(p.aplicar('66 99958-6623')).not_to eq(outro.aplicar('66 99958-6623'))
    end

    it 'dá pseudônimos diferentes para valores diferentes' do
      texto = p.aplicar('do 66 99958-6623 para o 66 99111-2222')

      expect(texto.scan(/\(66\) 90000-\d{4}/).uniq.size).to eq(2)
    end
  end

  describe 'o que é trocado' do
    it 'troca nome próprio conhecido, do mais longo para o mais curto' do
      # Sem a ordem por tamanho, trocar "Ana" antes de "Ana Paula" deixaria "Paula" solto.
      texto = p.aplicar('Ana Paula veio com a Ana', nomes: ['Ana', 'Ana Paula'])

      expect(texto).not_to include('Paula')
      expect(texto).not_to include('Ana')
    end

    it 'troca e-mail preservando a forma' do
      expect(p.aplicar('fulano@gmail.com')).to match(/\Acontato-\d+@exemplo\.invalido\z/)
    end

    it 'troca logradouro preservando a ordem de grandeza do número' do
      texto = p.aplicar('Av. das Figueiras, 1646')

      expect(texto).to match(/\ARua Fictícia, \d{4}\z/)
      expect(texto).not_to include('1646')
      expect(texto).not_to include('Figueiras')
    end

    it 'redige credencial sem apagar a chave que a nomeia' do
      expect(p.aplicar('senha: batatinha123')).to eq('senha: REDIGIDO')
    end

    # O vazamento real da primeira gravação da conv 41803: a lista dos 34 usuários da conta
    # estava carregada, o nome cadastrado é o completo, e a funcionária escreveu só o primeiro
    # nome. Trocar apenas o nome inteiro deixava o arquivo sair com ele.
    it 'troca o primeiro nome sozinho, e não só o nome cadastrado inteiro' do
      texto = p.aplicar('Me chamo Evellyn, sou consultora de locação', nomes: ['Evellyn Fernandes'])

      expect(texto).not_to include('Evellyn')
      expect(texto).to match(/\AMe chamo CONTATO-\d+, sou consultora de locação\z/)
    end

    it 'dá o mesmo pseudônimo ao primeiro nome e ao nome inteiro da mesma pessoa' do
      texto = p.aplicar('Evellyn Fernandes atendeu; a Evellyn retorna amanhã', nomes: ['Evellyn Fernandes'])

      expect(texto.scan(/CONTATO-\d+/).uniq.size).to eq(1)
    end

    # Pedaço solto sem fronteira acertaria palavra comum: "Ana" dentro de "Banana".
    it 'não troca pedaço de nome no meio de outra palavra' do
      expect(p.aplicar('comprei uma banana', nomes: ['Ana Paula'])).to eq('comprei uma banana')
    end
  end

  describe 'o papel no pseudônimo' do
    # Atendente que vira CONTATO-n apaga a distinção entre quem atende e quem é atendido, e a
    # conversa deixa de fazer sentido como cenário: não dá mais para ler quem transferiu.
    it 'atendente vira ATENDENTE-n e contato vira CONTATO-n' do
      texto = p.aplicar('Evellyn Fernandes atendeu Paula Souza',
                        nomes: { 'atendente' => ['Evellyn Fernandes'], 'contato' => ['Paula Souza'] })

      expect(texto).to match(/\AATENDENTE-\d+ atendeu CONTATO-\d+\z/)
    end

    it 'aceita lista simples e trata como contato' do
      expect(p.aplicar('Paula Souza ligou', nomes: ['Paula Souza'])).to match(/\ACONTATO-\d+ ligou\z/)
    end
  end

  describe 'o vocabulário protegido' do
    # A conta 6 tem nove agentes de IA com nome de gente — Letícia, Bruna, Marina, Helena,
    # Clara, Júlia, Feirão, Sofia e Rafa. Se uma atendente se chamar Clara, trocar o pedaço
    # solto faria a AGENTE Clara virar pseudônimo e a transferência perderia o sentido.
    subject(:p) { described_class.new(semente: 'fixture-1', protegidos: ['Clara', 'Parque Amazonas']) }

    it 'não troca nome de agente de IA que coincide com nome de atendente' do
      texto = p.aplicar('a Clara transferiu para o time',
                        nomes: { 'atendente' => ['Clara Fernandes'] })

      expect(texto).to eq('a Clara transferiu para o time')
    end

    # Sobrenome brasileiro é nome de bairro com frequência: Oliveira, Campos, Rocha, Lima.
    # Trocar o pedaço apagaria dado de negócio do cenário.
    it 'não troca pedaço de nome que também é bairro ou empreendimento' do
      texto = p.aplicar('casa no Parque Amazonas',
                        nomes: { 'atendente' => ['Rita Amazonas'] })

      expect(texto).to eq('casa no Parque Amazonas')
    end

    # A proteção vale só para o pedaço SOLTO. O nome cadastrado inteiro sai de qualquer jeito.
    it 'continua trocando o nome cadastrado inteiro, ainda que um pedaço seja protegido' do
      texto = p.aplicar('atendido por Clara Fernandes', nomes: { 'atendente' => ['Clara Fernandes'] })

      expect(texto).to match(/\Aatendido por ATENDENTE-\d+\z/)
    end
  end

  describe 'o registro de substituições' do
    # Quem revisa a fixture precisa ver o QUE foi trocado. O original fica de fora de
    # propósito: um registro com os dois lados seria a tabela de desanonimização.
    it 'diz tipo, pseudônimo e quantas vezes — nunca o original' do
      p.aplicar_em({ 'a' => 'Paula Souza ligou do 66 99958-6623',
                     'b' => 'Paula Souza de novo' },
                   nomes: { 'contato' => ['Paula Souza'] })

      contato = p.substituicoes.find { |s| s['tipo'] == 'contato' }
      expect(contato['ocorrencias']).to eq(2)
      expect(contato['pseudonimo']).to match(/\ACONTATO-\d+\z/)
      expect(p.substituicoes.map(&:keys).flatten.uniq).to contain_exactly('tipo', 'pseudonimo', 'ocorrencias')
      expect(p.substituicoes.to_s).not_to include('Paula')
    end

    it 'registra telefone e e-mail com o tipo certo' do
      p.aplicar('zap 66 99958-6623, e-mail fulano@gmail.com')

      expect(p.substituicoes.pluck('tipo')).to include('telefone', 'email')
    end

    it 'não registra nada quando não houve troca' do
      p.aplicar('tudo certo, obrigado')

      expect(p.substituicoes).to be_empty
    end
  end

  describe 'a marca do negócio' do
    subject(:p) { described_class.new(semente: 'fixture-1', marca: 'Tozi Imóveis') }

    # Um sócio cadastrado como usuário carrega o sobrenome da empresa. Trocar esse pedaço
    # apagaria o nome do negócio de toda fala da conversa — dano à fixture, sem ganho nenhum
    # de privacidade: o repositório inteiro é do cliente e a fixture se chama tozi-*.
    it 'não troca o pedaço do nome que também é a marca' do
      texto = p.aplicar('Aqui é da Tozi Imóveis, falo com o Rafael?', nomes: ['Rafael Tozi'])

      expect(texto).to include('Tozi Imóveis')
      expect(texto).not_to include('Rafael')
    end

    it 'continua trocando o nome cadastrado inteiro, marca ou não' do
      expect(p.aplicar('atendido por Rafael Tozi', nomes: ['Rafael Tozi'])).to match(/\Aatendido por CONTATO-\d+\z/)
    end
  end

  describe 'o que NÃO é trocado' do
    # O corpus perde o sentido se o assunto do atendimento sumir junto com o dado pessoal.
    it 'preserva preço, código, quantidade e bairro' do
      texto = '(cód 9908) Casa no Residencial Deville, 3 quartos, aluguel R$ 3.200, condomínio R$ 731,55'

      expect(p.aplicar(texto)).to eq(texto)
    end

    it 'preserva nome que não foi declarado como nome de pessoa' do
      expect(p.aplicar('imóvel no Jardim Paraíso')).to include('Jardim Paraíso')
    end
  end

  # O slug da página do imóvel pode carregar rua e número SEM a palavra "Rua", e aí a trava de
  # logradouro não pega. Em vez de reconhecer rua dentro do slug, o caminho inteiro é
  # normalizado — mas o CÓDIGO tem que sobreviver, porque é o dado de negócio do cenário.
  describe 'URL de imóvel' do
    it 'apaga o slug descritivo e preserva o código' do
      limpo = p.aplicar('vi esse https://www.toziimoveis.com.br/imovel/aluguel-casa-tarumas-1007-sinop-9412 ainda tem?')

      expect(limpo).to include('imovel-ficticio-9412')
      expect(limpo).not_to include('tarumas')
      expect(limpo).not_to include('1007')
    end

    # Regressão da primeira gravação real (conv 41803): havia duas regras de URL em sequência e
    # a segunda reescrevia a saída da primeira, levando o código junto com o slug.
    it 'não deixa uma segunda passada comer o código' do
      limpo = p.aplicar('https://www.toziimoveis.com.br/imovel/casa-sinop-9412')

      expect(limpo).not_to include('pagina-ficticia')
      expect(limpo).to end_with('imovel-ficticio-9412')
    end

    it 'apaga o caminho inteiro quando não há código' do
      limpo = p.aplicar('https://www.toziimoveis.com.br/quem-somos/nossa-historia')

      expect(limpo).to eq('https://www.toziimoveis.com.br/pagina-ficticia')
    end

    it 'preserva o host, que o fix_property_links precisa casar' do
      expect(p.aplicar('https://www.toziimoveis.com.br/imovel/casa-9412')).to include('toziimoveis.com.br')
    end

    it 'entrega URL que a trava aceita' do
      limpo = p.aplicar('https://www.toziimoveis.com.br/imovel/aluguel-casa-jardim-paraiso-sinop-9412')

      expect(Spx::Harness::Vazamento.varrer(limpo)).to be_empty
    end
  end

  describe '#aplicar_em' do
    # Telefone escondido num argumento de tool vazaria igual ao do texto da mensagem.
    it 'percorre hash e array aninhados' do
      estrutura = { 'args' => { 'telefone' => '66 99958-6623' },
                    'linhas' => ['contato: fulano@gmail.com', 'ok'] }

      limpo = p.aplicar_em(estrutura)

      expect(Spx::Harness::Vazamento.varrer(limpo.to_json)).to be_empty
      expect(limpo['linhas'].last).to eq('ok')
    end

    it 'não mexe em número, booleano e nil' do
      expect(p.aplicar_em({ 'a' => 3, 'b' => true, 'c' => nil })).to eq({ 'a' => 3, 'b' => true, 'c' => nil })
    end
  end
end
