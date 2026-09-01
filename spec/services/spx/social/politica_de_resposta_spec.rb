require 'rails_helper'

RSpec.describe Spx::Social::PoliticaDeResposta do
  subject(:politica) { described_class.new(account: account) }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  def configurar(config)
    account.update!(settings: (account.settings || {}).merge('social_reply' => config))
    account.reload
  end

  def comentario(atributos = {})
    create(:social_comentario, { account: account, inbox: inbox, autor_username: 'pauloseze' }.merge(atributos))
  end

  # 🔴 A regra que impede o vazamento. O padrão oposto — lista vazia libera todo mundo — é o
  # jeito clássico de a conta inteira começar a responder cliente real porque alguém ligou a
  # chave e esqueceu de preencher a lista.
  describe 'lista vazia' do
    it 'não libera ninguém quando a allowlist está vazia' do
      configurar('privada' => true, 'allowlist' => [])

      expect(politica.motivo_da_recusa(comentario, 'privada')).to eq(:fora_do_piloto)
    end

    it 'não libera ninguém quando a allowlist nem existe' do
      configurar('privada' => true)

      expect(politica.motivo_da_recusa(comentario, 'privada')).to eq(:fora_do_piloto)
    end

    it 'não libera ninguém quando não há configuração nenhuma' do
      expect(politica.motivo_da_recusa(comentario, 'privada')).to eq(:forma_desligada)
    end
  end

  describe 'allowlist' do
    before { configurar('privada' => true, 'allowlist' => ['pauloseze']) }

    it 'libera quem está na lista' do
      expect(politica).to be_permite(comentario, 'privada')
    end

    it 'recusa quem não está' do
      expect(politica.motivo_da_recusa(comentario(autor_username: 'outra_pessoa'), 'privada'))
        .to eq(:fora_do_piloto)
    end

    it 'ignora caixa e @ na comparação' do
      configurar('privada' => true, 'allowlist' => ['@PauloSeze'])

      expect(politica).to be_permite(comentario(autor_username: 'pauloseze'), 'privada')
    end

    it 'recusa comentário sem autor, em vez de deixar passar' do
      expect(politica.motivo_da_recusa(comentario(autor_username: nil), 'privada')).to eq(:fora_do_piloto)
    end

    # Sair do piloto é um ato explícito, não um efeito colateral de esvaziar a lista.
    it 'libera geral só com `todos` marcado' do
      configurar('privada' => true, 'allowlist' => [], 'todos' => true)

      expect(politica).to be_permite(comentario(autor_username: 'qualquer_um'), 'privada')
    end
  end

  describe 'as duas formas têm chave separada' do
    it 'liga a privada sem ligar a pública' do
      configurar('privada' => true, 'allowlist' => ['pauloseze'])

      expect(politica).to be_permite(comentario, 'privada')
      expect(politica.motivo_da_recusa(comentario, 'publica')).to eq(:forma_desligada)
    end

    it 'liga a pública sem ligar a privada' do
      configurar('publica' => true, 'allowlist' => ['pauloseze'])

      expect(politica).to be_permite(comentario, 'publica')
      expect(politica.motivo_da_recusa(comentario, 'privada')).to eq(:forma_desligada)
    end

    it 'recusa forma que não existe' do
      configurar('publica' => true, 'privada' => true, 'allowlist' => ['pauloseze'])

      expect(politica.motivo_da_recusa(comentario, 'carta_registrada')).to eq(:forma_desconhecida)
    end
  end

  describe 'guardas de sanidade' do
    before { configurar('publica' => true, 'privada' => true, 'todos' => true) }

    it 'nunca responde a um comentário da própria conta' do
      expect(politica.motivo_da_recusa(comentario(proprio: true), 'publica'))
        .to eq(:comentario_da_propria_conta)
    end

    # A privada é UMA por comentário e não tem segunda chance.
    it 'recusa quando aquela forma já foi aceita pela Meta' do
      c = comentario
      c.registrar_resposta!('privada', external_id: 'aWdt-123')

      expect(politica.motivo_da_recusa(c, 'privada')).to eq(:ja_respondido)
    end

    # Tentativa que falhou NÃO conta como respondida — senão uma recusa da Meta esconderia
    # para sempre um cliente sem resposta.
    it 'deixa tentar de novo quando a tentativa anterior falhou' do
      c = comentario
      c.registrar_resposta!('privada', external_id: nil, erro: '100/2534014 usuário não encontrado')

      expect(politica).to be_permite(c, 'privada')
    end

    it 'uma forma respondida não bloqueia a outra' do
      c = comentario
      c.registrar_resposta!('privada', external_id: 'aWdt-123')

      expect(politica).to be_permite(c, 'publica')
    end
  end
end
