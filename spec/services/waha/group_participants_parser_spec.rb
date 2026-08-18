# frozen_string_literal: true

require 'rails_helper'

# As fixtures reproduzem o schema EXATO medido ao vivo contra a WAHA 2026.4.2
# (engine GOWS) — inclusive `DisplayName` vazio, `PhoneNumber` com sufixo
# @s.whatsapp.net e `pn` com sufixo @c.us. Só os números foram trocados por
# fictícios.
RSpec.describe Waha::GroupParticipantsParser do
  let(:v1) { JSON.parse(file_fixture('waha/group_participants.json').read) }
  let(:v2) { JSON.parse(file_fixture('waha/group_participants_v2.json').read) }
  let(:groups) { JSON.parse(file_fixture('waha/groups.json').read) }

  describe '.parse' do
    it 'normaliza o shape do engine (/participants) para o contrato C3' do
      expect(described_class.parse(v1)).to eq(
        [
          { 'lid' => '229480102662169', 'phone' => '556699990001', 'name' => nil, 'admin' => true },
          { 'lid' => '224515288227943', 'phone' => '556699990002', 'name' => nil, 'admin' => false },
          { 'lid' => '267722592149653', 'phone' => '556699990003', 'name' => nil, 'admin' => true }
        ]
      )
    end

    it 'normaliza o shape v2 para exatamente o mesmo resultado' do
      expect(described_class.parse(v2)).to eq(described_class.parse(v1))
    end

    it 'trata superadmin como admin' do
      expect(described_class.parse(v2).last['admin']).to be(true)
    end

    it 'extrai os participantes de dentro do payload de GET /groups' do
      participants = described_class.parse(groups)

      expect(participants.size).to eq(3)
      expect(participants.pluck('phone')).to contain_exactly('556699990001', '556699990002', '556699990004')
    end

    it 'devolve telefone e lid apenas com dígitos, sem sufixo de JID' do
      expect(described_class.parse(v1).first.values_at('lid', 'phone')).to all(match(/\A\d+\z/))
    end

    it 'mantém name nil quando DisplayName vem vazio (sempre, no GOWS)' do
      expect(described_class.parse(v1).pluck('name')).to all(be_nil)
    end

    it 'usa DisplayName quando o engine devolve algo' do
      raw = [v1.first.merge('DisplayName' => 'Rogerio José Da Silva')]

      expect(described_class.parse(raw).first['name']).to eq('Rogerio José Da Silva')
    end

    it 'trata participante endereçado por telefone (sem LID)' do
      raw = [{ 'JID' => '556699990009@s.whatsapp.net', 'PhoneNumber' => '', 'LID' => '', 'IsAdmin' => false }]

      expect(described_class.parse(raw)).to eq([{ 'lid' => nil, 'phone' => '556699990009', 'name' => nil, 'admin' => false }])
    end

    it 'descarta entradas sem lid e sem telefone' do
      expect(described_class.parse([{ 'JID' => '', 'PhoneNumber' => '' }, 'lixo', nil])).to be_empty
    end

    it 'nunca levanta em entrada inesperada' do
      expect(described_class.parse(nil)).to eq([])
      expect(described_class.parse('erro')).to eq([])
      expect(described_class.parse({ 'message' => 'Session does not exist' })).to eq([])
    end
  end

  describe '.lid_pn_pairs' do
    it 'devolve pares prontos para o cache, só com os dois lados preenchidos' do
      expect(described_class.lid_pn_pairs(v1)).to eq(
        [%w[229480102662169 556699990001], %w[224515288227943 556699990002], %w[267722592149653 556699990003]]
      )
    end

    it 'ignora participante sem LID' do
      raw = [{ 'JID' => '556699990009@s.whatsapp.net', 'PhoneNumber' => '556699990009@s.whatsapp.net' }]

      expect(described_class.lid_pn_pairs(raw)).to be_empty
    end
  end

  describe '.digits' do
    it 'normaliza qualquer forma de JID/telefone para dígitos' do
      expect(described_class.digits('556699990001@s.whatsapp.net')).to eq('556699990001')
      expect(described_class.digits('556699990001@c.us')).to eq('556699990001')
      expect(described_class.digits('+55 66 9999-0001')).to eq('556699990001')
    end

    it 'devolve nil para vazio ou sem dígito' do
      expect(described_class.digits(nil)).to be_nil
      expect(described_class.digits('')).to be_nil
      expect(described_class.digits('@lid')).to be_nil
    end
  end
end
