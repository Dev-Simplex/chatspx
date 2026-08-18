require 'rails_helper'

# A resolução é onde mora a lógica desta frente: exceção de unidade vence exceção de etiqueta,
# que vence o horário padrão; mais específico vence; empate, a criada por último. Errar aqui é
# mentir pro cliente sobre porta aberta — por isso cada regra tem um exemplo próprio.
RSpec.describe Spx::Unidade do
  let(:account) { create(:account) }
  let(:unidade) { create(:spx_unidade, account: account, cidade: 'Cuiabá', etiquetas: ['MT', 'Capital']) }

  # 2026-08-24 é segunda-feira; 2026-08-23 é domingo.
  let(:segunda) { Date.new(2026, 8, 24) }
  let(:domingo) { Date.new(2026, 8, 23) }

  def horario(dia_semana, abre: '08:00', fecha: '18:00', fechada: false)
    create(:spx_unidade_horario, unidade: unidade, dia_semana: dia_semana, abre: abre, fecha: fecha, fechada: fechada)
  end

  def excecao(data, **attrs)
    create(:spx_unidade_excecao, { account: account, data_inicio: data, data_fim: data }.merge(attrs))
  end

  describe 'horário padrão' do
    it 'devolve a faixa cadastrada para o dia da semana' do
      horario(1)

      expect(unidade.estado_em(segunda).faixas.map(&:to_s)).to eq(['08:00 às 18:00'])
    end

    it 'fecha quando o dia está cadastrado como fechado' do
      horario(0, fechada: true, abre: nil, fecha: nil)

      expect(unidade.estado_em(domingo)).not_to be_aberta
    end

    it 'aceita grade partida no mesmo dia e devolve as faixas em ordem' do
      horario(1, abre: '14:00', fecha: '18:00')
      horario(1, abre: '08:00', fecha: '12:00')

      expect(unidade.estado_em(segunda).faixas.map(&:to_s)).to eq(['08:00 às 12:00', '14:00 às 18:00'])
    end

    it 'distingue dia sem cadastro de dia fechado' do
      horario(1)

      expect(unidade.estado_em(domingo).faixas).to be_empty
      expect(unidade.horario_cadastrado?).to be(true)
      expect(create(:spx_unidade, account: account).horario_cadastrado?).to be(false)
    end
  end

  describe 'precedência entre exceções' do
    before { horario(0, abre: '08:00', fecha: '12:00') }

    it 'exceção de etiqueta vence o horário padrão' do
      excecao(domingo, etiqueta: 'MT', abre: '09:00', fecha: '15:00', motivo: 'campanha')

      estado = unidade.estado_em(domingo)
      expect(estado.faixas.map(&:to_s)).to eq(['09:00 às 15:00'])
      expect(estado.motivo).to eq('campanha')
      expect(estado).to be_por_excecao
    end

    it 'exceção de unidade vence exceção de etiqueta' do
      excecao(domingo, etiqueta: 'MT', abre: '09:00', fecha: '15:00')
      excecao(domingo, unidade: unidade, fechada: true, motivo: 'reforma')

      expect(unidade.estado_em(domingo)).not_to be_aberta
      expect(unidade.estado_em(domingo).motivo).to eq('reforma')
    end

    it 'exceção da conta inteira vale, e perde para a de etiqueta' do
      conta_inteira = excecao(domingo, fechada: true, motivo: 'feriado nacional')

      expect(unidade.estado_em(domingo).motivo).to eq('feriado nacional')

      excecao(domingo, etiqueta: 'MT', abre: '10:00', fecha: '14:00', motivo: 'exceção regional')
      expect(unidade.estado_em(domingo).faixas.map(&:to_s)).to eq(['10:00 às 14:00'])
      expect(conta_inteira.especificidade).to be < 1
    end

    it 'no empate de especificidade vence a criada por último' do
      excecao(domingo, etiqueta: 'MT', abre: '09:00', fecha: '15:00', motivo: 'primeira')
      excecao(domingo, etiqueta: 'Capital', abre: '11:00', fecha: '13:00', motivo: 'segunda')

      expect(unidade.estado_em(domingo).motivo).to eq('segunda')
    end

    it 'exceção que não fecha e não traz horário devolve a unidade ao horário de sempre' do
      excecao(domingo, fechada: true, motivo: 'feriado nacional')
      excecao(domingo, unidade: unidade, fechada: false, motivo: 'esta abre normal')

      estado = unidade.estado_em(domingo)
      expect(estado.faixas.map(&:to_s)).to eq(['08:00 às 12:00'])
      expect(estado.motivo).to eq('esta abre normal')
    end
  end

  describe 'alcance da exceção' do
    before { horario(0, abre: '08:00', fecha: '12:00') }

    it 'ignora exceção fora do intervalo de datas' do
      excecao(domingo - 1, fechada: true)

      expect(unidade.estado_em(domingo)).to be_aberta
    end

    it 'aplica exceção de intervalo em qualquer dia dentro dele' do
      create(:spx_unidade_excecao, account: account, unidade: unidade,
                                   data_inicio: domingo - 2, data_fim: domingo + 2, fechada: true)

      expect(unidade.estado_em(domingo)).not_to be_aberta
    end

    it 'ignora exceção de etiqueta que a unidade não carrega' do
      excecao(domingo, etiqueta: 'GO', fechada: true)

      expect(unidade.estado_em(domingo)).to be_aberta
    end

    it 'casa a etiqueta sem depender de acento nem de caixa' do
      unidade.update!(etiquetas: ['Região Norte'])
      excecao(domingo, etiqueta: 'regiao norte', fechada: true)

      expect(unidade.estado_em(domingo)).not_to be_aberta
    end

    it 'ignora exceção de outra conta' do
      outra = create(:account)
      create(:spx_unidade_excecao, account: outra, data_inicio: domingo, data_fim: domingo, fechada: true)

      expect(unidade.estado_em(domingo)).to be_aberta
    end

    it 'usa o escopo de exceções já carregado quando ele é passado' do
      excecao(domingo, fechada: true)

      expect(unidade.estado_em(domingo, escopo_excecoes: [])).to be_aberta
    end
  end

  describe 'relógio de parede' do
    it 'diz se o minuto do dia cai dentro de alguma faixa' do
      horario(1, abre: '08:00', fecha: '12:00')
      estado = unidade.estado_em(segunda)

      expect(estado.aberta_em?((9 * 60) + 30)).to be(true)
      expect(estado.aberta_em?(13 * 60)).to be(false)
    end

    it 'trata faixa que atravessa a meia-noite' do
      horario(1, abre: '18:00', fecha: '02:00')
      estado = unidade.estado_em(segunda)

      expect(estado.aberta_em?(23 * 60)).to be(true)
      expect(estado.aberta_em?(1 * 60)).to be(true)
      expect(estado.aberta_em?(10 * 60)).to be(false)
    end
  end

  describe '#zona' do
    it 'usa o fuso cadastrado na unidade' do
      expect(create(:spx_unidade, account: account, timezone: 'America/Sao_Paulo').zona.name).to eq('America/Sao_Paulo')
    end

    it 'cai no fuso padrão quando o cadastrado não existe' do
      unidade.update!(timezone: 'America/Nao_Existe')

      expect(unidade.zona.name).to eq(described_class::FUSO_PADRAO)
    end
  end

  describe 'escopo e validação' do
    it 'ativas não traz unidade desativada' do
      unidade
      create(:spx_unidade, account: account, ativa: false)

      expect(described_class.ativas.where(account_id: account.id)).to contain_exactly(unidade)
    end

    it 'exige slug único por conta' do
      duplicada = build(:spx_unidade, account: account, slug: unidade.slug)

      expect(duplicada).not_to be_valid
    end

    it 'normaliza as etiquetas na gravação' do
      registro = create(:spx_unidade, account: account, etiquetas: ['  MT ', 'Região', 'mt'])

      expect(registro.etiquetas).to eq(%w[mt regiao])
    end
  end
end
