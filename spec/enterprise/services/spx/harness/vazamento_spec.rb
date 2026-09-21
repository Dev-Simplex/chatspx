require 'rails_helper'

# A trava é a SEGUNDA rede. O Pseudonimizador troca os valores; esta classe existe para o dia
# em que ele deixar um padrão passar. Por isso os exemplos de falso positivo pesam tanto quanto
# os de captura: trava que grita em preço de imóvel seria desligada na primeira semana.
RSpec.describe Spx::Harness::Vazamento do
  describe '.conferir!' do
    it 'deixa passar texto limpo, devolvendo-o para encadear' do
      expect(described_class.conferir!('Casa no Centro, 3 quartos', origem: 'x')).to eq('Casa no Centro, 3 quartos')
    end

    it 'levanta nomeando o padrão e dizendo que a fixture não foi gravada' do
      expect { described_class.conferir!('me chama no 66 99958-6623', origem: 'fixture-y') }
        .to raise_error(described_class::Encontrado, /telefone.*fixture-y|fixture-y.*telefone/m)
    end

    it 'diz para consertar o pseudonimizador, não a trava' do
      expect { described_class.conferir!('cliente@gmail.com', origem: 'x') }
        .to raise_error(described_class::Encontrado, /Corrija o Pseudonimizador/)
    end
  end

  describe 'o que precisa ser pego' do
    [
      ['telefone com DDD e nove', '66 99958-6623'],
      ['telefone entre parênteses', '(66) 3531-7222'],
      ['telefone com +55', '+55 66 99958-6623'],
      ['telefone sem formatação', 'liga 66995866623 hoje'],
      ['e-mail', 'fulano.silva@gmail.com'],
      ['logradouro com número', 'Av. das Figueiras, 1646'],
      ['logradouro sem vírgula', 'Rua dos Ipês 880'],
      ['logradouro com nº', 'Travessa Brasil, nº 45'],
      ['senha', 'senha: umaSenhaQualquer'],
      ['token', 'api_key = abc123def456'],
      ['chave sk-', 'sk-proj-AAAAAAAAAAAAAAAAAAAA']
    ].each do |rotulo, texto|
      it "pega #{rotulo}" do
        expect(described_class.varrer(texto)).not_to be_empty
      end
    end
  end

  # Estes são os números que a fixture PRECISA conservar: são o assunto do atendimento.
  describe 'o que não pode ser confundido com dado sensível' do
    [
      ['preço', 'o aluguel é R$ 3.200 por mês'],
      ['preço com centavos', 'condomínio R$ 731,55'],
      ['código de imóvel', '(cód 9908) Casa no Jardim Paraíso'],
      ['quantidade', '3 quartos, 2 suítes, 1 vaga'],
      ['CEP', 'CEP 78550-000'],
      ['data e hora', 'quarta-feira, 02/09/2026 às 14:31'],
      ['metragem', 'área total 250 m²'],
      ['bairro sem número', 'Casa no Residencial Deville'],
      ['horário comercial', 'das 7h30 às 11h30 e das 13h30 às 17h30'],
      ['ano', 'entrega prevista para 2027']
    ].each do |rotulo, texto|
      it "não acusa #{rotulo}" do
        expect(described_class.varrer(texto)).to be_empty
      end
    end
  end

  # CPF e CNPJ entram por DÍGITO VERIFICADOR, não por formato. É o que separa documento de
  # telefone de 11 dígitos sem heurística frágil — e o que impede preço, CEP e código de imóvel
  # de virarem falso positivo. Os CPF/CNPJ abaixo são matematicamente válidos e fictícios.
  describe 'documento' do
    [
      ['CPF pontuado', 'meu CPF é 529.982.247-25'],
      ['CPF sem pontuação', 'cpf 52998224725 ok'],
      ['CNPJ pontuado', 'CNPJ 11.222.333/0001-81'],
      ['CNPJ sem pontuação', 'cnpj 11222333000181'],
      ['RG pontuado', 'RG 12.345.678-9'],
      ['RG rotulado', 'rg: 1234567-8']
    ].each do |rotulo, texto|
      it "pega #{rotulo}" do
        expect(described_class.varrer(texto)).not_to be_empty
      end
    end

    # O conflito real do conjunto: celular com DDD também tem 11 dígitos. Ele TEM que ser
    # acusado — como telefone, nunca como documento.
    it 'acusa telefone de 11 dígitos como telefone, não como documento' do
      achados = described_class.varrer('66999586623')

      expect(achados.join).to include('telefone')
      expect(achados.join).not_to include('documento')
    end

    [
      ['preço alto', 'imóvel de R$ 1.250.000,00'],
      ['CEP', 'CEP 78550-000'],
      ['código de imóvel', 'cód 9908 e cód 112233'],
      ['sequência repetida', '11111111111'],
      ['número de protocolo', 'protocolo 20260902143100'],
      ['medida', 'área de 12345678 cm²']
    ].each do |rotulo, texto|
      it "não acusa #{rotulo} como documento" do
        expect(described_class.varrer(texto).join).not_to include('documento')
      end
    end
  end

  # O buraco que a trava de logradouro não cobre: slug carrega rua e número sem a palavra "Rua".
  describe 'slug de URL' do
    it 'pega slug descritivo com rua e número embutidos' do
      texto = 'https://www.toziimoveis.com.br/imovel/casa-tarumas-1007-sinop-9412'

      expect(described_class.varrer(texto).join).to include('slug')
    end

    it 'pega slug sem número também' do
      texto = 'https://www.toziimoveis.com.br/imovel/aluguel-casa-santorini-residence-sinop'

      expect(described_class.varrer(texto).join).to include('slug')
    end

    it 'aceita a forma normalizada que o Pseudonimizador produz' do
      expect(described_class.varrer('https://www.toziimoveis.com.br/imovel/imovel-ficticio-9412')).to be_empty
    end

    it 'aceita URL curta sem slug descritivo' do
      expect(described_class.varrer('https://www.toziimoveis.com.br/contato')).to be_empty
    end
  end

  # Sem isto a trava derrubaria a própria saída do pseudonimizador, e o gravador nunca gravaria.
  describe 'os próprios pseudônimos' do
    it 'não acusa o telefone, e-mail, nome e endereço fictícios' do
      texto = 'CONTATO-42 (contato-7@exemplo.invalido) mora na Rua Fictícia, 1646 e atende no (66) 90000-0037'

      expect(described_class.varrer(texto)).to be_empty
    end
  end
end
