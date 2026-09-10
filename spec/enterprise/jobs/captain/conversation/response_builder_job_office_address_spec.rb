require 'rails_helper'

# A `buscar_unidades` responde certo quando é chamada — o problema é que ela nem sempre é
# chamada, e conduta não força chamada de ferramenta. Medido na Tozi em 90 dias: das 49 vezes
# em que a IA deu o endereço do escritório, 22 estavam erradas, e nunca o mesmo endereço.
RSpec.describe Captain::Conversation::ResponseBuilderJob do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:job) { described_class.new }
  let(:endereco) { 'Av. das Figueiras, 1646 - Sala 01, Centro, Sinop/MT' }

  before { job.instance_variable_set(:@conversation, conversation) }

  def corrigir(texto)
    job.send(:fix_office_address, texto)
  end

  def cadastrar_unidade!(ativa: true, endereco_valor: nil)
    Unit.create!(account_id: account.id, name: "Unidade #{SecureRandom.hex(3)}", city: 'Sinop',
                 state: 'MT', active: ativa, timezone: 'America/Cuiaba',
                 address: endereco_valor.nil? ? endereco : endereco_valor)
  end

  context 'when the account has no unit registered' do
    it 'não toca em nada — a guarda é opt-in por dado' do
      texto = 'O escritório fica na Avenida dos Tarumãs, 1260 - Jardim das Violetas.'

      expect(corrigir(texto)).to eq(texto)
    end
  end

  context 'when the account has one active unit' do
    before { cadastrar_unidade! }

    # A frase real da conv 41549, dita a um cliente que estava saindo de casa naquele momento.
    it 'corrige o endereço inventado do escritório' do
      resultado = corrigir('Perfeito! O escritório fica na Avenida dos Tarumãs, 1260 - Jardim das Violetas.')

      expect(resultado).to include('Av. das Figueiras, 1646')
      expect(resultado).not_to include('Tarumãs')
    end

    it 'corrige nas outras formas em que a IA se apresenta' do
      %w[ficamos estamos].each do |verbo|
        resultado = corrigir("#{verbo.capitalize} na Av. das Embaúbas, 1593 - Setor Comercial.")

        expect(resultado).to include('Figueiras'), "falhou em: #{verbo}"
      end
      expect(corrigir('A gente fica na Av. das Avencas, 1581.')).to include('Figueiras')
      expect(corrigir('Nosso endereço é Rua das Avencas, 1280, Jardim Botânico.')).to include('Figueiras')
    end

    it 'deixa passar quando o endereço já é o certo, mesmo abreviado diferente' do
      texto = 'Nosso escritório fica na Avenida das Figueiras, 1646, Centro.'

      expect(corrigir(texto)).to eq(texto)
    end

    # O maior risco da guarda: endereço de IMÓVEL é informação legítima em locação, e trocá-lo
    # mandaria a pessoa para o lugar errado — o estrago que se está tentando evitar.
    it 'NÃO toca no endereço de um imóvel' do
      texto = 'Essa kitnet fica na Rua Rogério Adriano Saconi, 286, no Jardim dos Tarumãs.'

      expect(corrigir(texto)).to eq(texto)
    end

    # Frase real: o endereço do imóvel e a menção ao escritório convivem na mesma resposta.
    it 'corrige só a frase do escritório, preservando a do imóvel' do
      texto = <<~TXT.strip
        Fica na Rua dos Antúrios, 234 casa A. Como o imóvel não fica em condomínio fechado,
        você pode passar no nosso escritório.
      TXT

      resultado = corrigir(texto)

      expect(resultado).to include('Rua dos Antúrios, 234')
      expect(resultado).to eq(texto)
    end

    it 'não inventa endereço quando a frase fala do escritório sem citar rua' do
      texto = 'Você passa no nosso escritório, deixa um documento com foto e retira a chave.'

      expect(corrigir(texto)).to eq(texto)
    end

    it 'não mexe em texto sem logradouro nenhum' do
      expect(corrigir('Oi! Tudo bem?')).to eq('Oi! Tudo bem?')
    end

    it 'aceita conteúdo vazio sem estourar' do
      expect(corrigir('')).to eq('')
      expect(corrigir(nil)).to be_nil
    end
  end

  # Rede com filiais: escolher uma das unidades por conta própria mandaria o cliente para a
  # loja errada. Sem resposta única, a guarda se cala.
  context 'when the account has more than one active unit' do
    before do
      cadastrar_unidade!
      cadastrar_unidade!(endereco_valor: 'Av. Brasil, 100, Centro, Sorriso/MT')
    end

    it 'não corrige, porque não há endereço único a apontar' do
      texto = 'O escritório fica na Avenida dos Tarumãs, 1260.'

      expect(corrigir(texto)).to eq(texto)
    end
  end

  context 'when the unit is inactive' do
    before { cadastrar_unidade!(ativa: false) }

    it 'ignora unidade desativada' do
      texto = 'O escritório fica na Avenida dos Tarumãs, 1260.'

      expect(corrigir(texto)).to eq(texto)
    end
  end
end
