require 'rails_helper'

# Bloco 4.15 — os tres estados. O que este arquivo protege acima de tudo e a regra de que
# `hmac_mandatory` nao muda de comportamento: a frota tem clientes integrados nele.
RSpec.describe Inbox do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_widget, account: account) }
  let(:inbox) { channel.inbox }

  describe '#resolved_identity_enforcement' do
    it 'e desativado na inbox que nunca abriu a tela' do
      expect(inbox.identity_enforcement).to be_nil
      expect(inbox.resolved_identity_enforcement).to eq('desativado')
    end

    it 'e obrigatorio quando hmac_mandatory esta ligado, sem nada gravado no jsonb' do
      channel.update!(hmac_mandatory: true)

      expect(inbox.reload.identity_enforcement).to be_nil
      expect(inbox.resolved_identity_enforcement).to eq('obrigatorio')
    end

    it 'le observado do jsonb' do
      inbox.update!(identity_enforcement: 'observado')

      expect(inbox.reload.resolved_identity_enforcement).to eq('observado')
    end

    it 'le obrigatorio do jsonb mesmo com hmac_mandatory desligado' do
      inbox.update!(identity_enforcement: 'obrigatorio')

      expect(inbox.reload.resolved_identity_enforcement).to eq('obrigatorio')
    end

    # A regra que protege a frota: o jsonb pode ENDURECER, nunca afrouxar.
    #
    # A ordem aqui (gravar primeiro, endurecer o canal depois) e a unica pela qual esse
    # valor ainda consegue existir desde que a escrita ignorada passou a ser recusada — e e
    # tambem a ordem real de uma inbox de cliente que ja tinha estado configurado quando o
    # HMAC obrigatorio foi ligado. Escrever `desativado` COM o canal ja mandatory agora
    # levanta RecordInvalid, e isso e o assunto do bloco `escrita que seria ignorada`.
    it 'nao deixa o jsonb afrouxar uma inbox que hoje exige assinatura' do
      inbox.update!(identity_enforcement: 'desativado')
      channel.update!(hmac_mandatory: true)
      expect(inbox.reload.resolved_identity_enforcement).to eq('obrigatorio')

      inbox.update_columns(additional_attributes: { 'identity_enforcement' => 'observado' }) # rubocop:disable Rails/SkipsModelValidations
      expect(inbox.reload.resolved_identity_enforcement).to eq('obrigatorio')
    end

    it 'ignora valor desconhecido em vez de operar num estado inexistente' do
      # Grava por baixo da validacao de proposito: e o que uma linha antiga, ou uma
      # escrita direta no banco, deixaria para tras.
      inbox.update_columns(additional_attributes: { 'identity_enforcement' => 'quase_obrigatorio' }) # rubocop:disable Rails/SkipsModelValidations

      expect(inbox.reload.resolved_identity_enforcement).to eq('desativado')
    end
  end

  describe 'validacao do estado' do
    it 'recusa estado que nao existe, com erro legivel' do
      inbox.identity_enforcement = 'meio_obrigatorio'

      expect(inbox).not_to be_valid
      expect(inbox.errors[:identity_enforcement])
        .to eq(['is not a valid identity enforcement state (accepted values: desativado, observado, obrigatorio)'])
    end

    it 'aceita os tres estados' do
      %w[desativado observado obrigatorio].each do |state|
        inbox.identity_enforcement = state
        expect(inbox).to be_valid
      end
    end

    it 'aceita nil, que e a inbox que nunca abriu a tela' do
      inbox.identity_enforcement = nil

      expect(inbox).to be_valid
    end
  end

  # §12 do ESTADO-BLOCOS-DEFINITIVO, item 7. A precedencia entre `hmac_mandatory` e o valor
  # gravado continua sendo decisao do dono (ver a ESCALACAO no fim deste arquivo). O que
  # NAO depende da decisao, e que a propria pergunta ja registra, e que a API nao pode
  # aceitar em silencio uma escrita que sera ignorada: hoje o PATCH grava `observado` numa
  # inbox `hmac_mandatory`, devolve 200, e a leitura seguinte devolve `obrigatorio`. O
  # administrador sai da tela convencido de que ligou a observacao, e o relatorio que ele
  # vai abrir depois mede um estado que nunca entrou em vigor.
  #
  # A recusa NAO muda o comportamento de nenhuma inbox da frota: `resolved_identity_enforcement`
  # continua exatamente como estava. Ela so tira o silencio.
  describe 'escrita que seria ignorada — recusada em vez de aceita e descartada' do
    before { channel.update!(hmac_mandatory: true) }

    # O texto e conferido INTEIRO, e nao por um pedaco: o `default:` do `I18n.t` no concern
    # e deliberadamente diferente do texto traduzido, entao esta linha so passa se a chave
    # existir mesmo no `en.yml`. Conferir um pedaco comum aos dois passaria com a chave
    # ausente e nao mediria traducao nenhuma.
    it 'recusa observado, com o erro traduzido que NOMEIA o hmac_mandatory' do
      inbox.identity_enforcement = 'observado'

      expect(inbox).not_to be_valid
      expect(inbox.errors[:identity_enforcement]).to eq(
        ['cannot be relaxed on this inbox: the channel\'s mandatory HMAC already forces "obrigatorio", ' \
         'and the value stored here would be ignored']
      )
    end

    it 'recusa desativado pelo mesmo motivo' do
      inbox.identity_enforcement = 'desativado'

      expect(inbox).not_to be_valid
    end

    # `obrigatorio` nao e ignorado: e exatamente o que a inbox ja faz. Recusar tambem este
    # transformaria a guarda num "esta inbox nao aceita mais nenhum estado", que e outro
    # comportamento e nao o que a §12 pede.
    it 'aceita obrigatorio, que concorda com o que a inbox ja faz' do
      inbox.identity_enforcement = 'obrigatorio'

      expect(inbox).to be_valid
    end

    # LIMPAR a chave nao e afrouxar: sem ela a leitura devolve `obrigatorio` do mesmo
    # jeito, porque quem responde e o `hmac_mandatory`. Recusar a limpeza deixaria o
    # administrador preso ao valor herdado, sem nenhum ganho de seguranca.
    it 'deixa LIMPAR a chave, que nao afrouxa nada' do
      inbox.update_columns(additional_attributes: { 'identity_enforcement' => 'observado' }) # rubocop:disable Rails/SkipsModelValidations

      expect(inbox.reload.update(identity_enforcement: nil)).to be(true)
      expect(inbox.reload.resolved_identity_enforcement).to eq('obrigatorio')
    end

    # Estado que nao existe ja tem dono — `ensure_valid_identity_enforcement`. Se esta
    # guarda tambem opinasse sobre ele, o mesmo campo voltaria DOIS erros contraditorios
    # ("nao existe" e "nao pode ser afrouxado") para um unico valor digitado errado.
    it 'nao opina sobre estado inexistente — quem responde por ele e a outra validacao' do
      inbox.identity_enforcement = 'meio_obrigatorio'

      expect(inbox).not_to be_valid
      expect(inbox.errors[:identity_enforcement].size).to eq(1)
      expect(inbox.errors[:identity_enforcement].first).to include('not a valid identity enforcement state')
    end

    # A frota inteira cai aqui: quase nenhuma inbox `hmac_mandatory` tem a chave gravada.
    # Se a guarda disparasse com a chave ausente, TODA inbox com HMAC obrigatorio ficaria
    # impossivel de salvar — e o sintoma apareceria em telas que nao tem nada a ver com
    # enforcement.
    it 'nao atrapalha a inbox mandatory que nunca gravou a chave' do
      expect(inbox.identity_enforcement).to be_nil

      expect(inbox.update(name: 'Outro nome')).to be(true)
    end

    # A inbox que ja carrega o valor de antes de o canal virar mandatory nao pode ficar
    # impossivel de salvar: trocar o nome dela, o horario de atendimento ou qualquer outra
    # coisa passaria a levantar RecordInvalid num campo que o formulario nem toca.
    it 'NAO trava o salvamento de uma inbox que ja carregava o valor herdado' do
      inbox.update_columns(additional_attributes: { 'identity_enforcement' => 'observado' }) # rubocop:disable Rails/SkipsModelValidations

      expect(inbox.reload.update(name: 'Outro nome')).to be(true)
      expect(inbox.reload.identity_enforcement).to eq('observado')
    end
  end

  describe 'sem hmac_mandatory nada e recusado' do
    it 'aceita os tres estados na inbox comum' do
      %w[desativado observado obrigatorio].each do |state|
        expect(inbox.update(identity_enforcement: state)).to be(true)
      end
    end
  end

  describe 'marca de inicio da observacao' do
    it 'nasce quando o estado entra em observado' do
      expect(inbox.identity_enforcement_observed_since).to be_nil

      inbox.update!(identity_enforcement: 'observado')

      expect(inbox.reload.identity_enforcement_observed_since_time).to be_within(30.seconds).of(Time.zone.now)
    end

    it 'nao se move quando a inbox e salva de novo ja em observado' do
      inbox.update!(identity_enforcement: 'observado')
      marca = inbox.reload.identity_enforcement_observed_since

      inbox.update!(name: 'Outro nome')

      expect(inbox.reload.identity_enforcement_observed_since).to eq(marca)
    end

    it 'nao nasce em desativado nem em obrigatorio' do
      inbox.update!(identity_enforcement: 'obrigatorio')

      expect(inbox.reload.identity_enforcement_observed_since).to be_nil
    end
  end

  describe 'consultas de conveniencia' do
    it 'watching? cobre observado e obrigatorio, e so eles' do
      inbox.update!(identity_enforcement: 'desativado')
      expect(inbox.identity_enforcement_watching?).to be(false)

      inbox.update!(identity_enforcement: 'observado')
      expect(inbox.identity_enforcement_watching?).to be(true)

      inbox.update!(identity_enforcement: 'obrigatorio')
      expect(inbox.identity_enforcement_watching?).to be(true)
    end
  end
end
