require 'rails_helper'

RSpec.describe Whatsapp::GroupSenderExtractor do
  # U+200E (LEFT-TO-RIGHT MARK) — invisivel, vem colado no nome pela WAHA.
  let(:lrm) { "\u200E" }

  describe '.call' do
    context 'with the real WAHA format (name + LID)' do
      let(:content) { "👥 *#{lrm}Rogerio José Da Silva (229480102662169@lid)*\n\nQual Wi-Fi está?" }

      it 'devolve o texto limpo' do
        expect(described_class.call(content).content).to eq('Qual Wi-Fi está?')
      end

      it 'devolve o autor no shape do contrato C2' do
        expect(described_class.call(content).sender).to eq(
          'name' => 'Rogerio José Da Silva', 'lid' => '229480102662169', 'phone' => nil
        )
      end

      it 'marca que o prefixo estava presente' do
        expect(described_class.call(content)).to be_matched
      end
    end

    context 'when the author has no LID' do
      let(:content) { "👥 *Angela Tozi*\n\ntexto" }

      it 'extrai so o nome' do
        expect(described_class.call(content).sender).to eq('name' => 'Angela Tozi', 'lid' => nil, 'phone' => nil)
      end

      it 'limpa o texto' do
        expect(described_class.call(content).content).to eq('texto')
      end
    end

    context 'when the author is a phone number instead of a name' do
      it 'reconhece telefone formatado' do
        result = described_class.call("👥 *+55 66 99999-1234*\n\noi")
        expect(result.sender).to eq('name' => nil, 'lid' => nil, 'phone' => '5566999991234')
      end

      it 'reconhece o JID de usuario (@c.us) como telefone' do
        result = described_class.call("👥 *5566999991234@c.us*\n\noi")
        expect(result.sender).to eq('name' => nil, 'lid' => nil, 'phone' => '5566999991234')
      end

      it 'reconhece nome + telefone entre parenteses' do
        result = described_class.call("👥 *Vilso Tozi (5566999991234@c.us)*\n\noi")
        expect(result.sender).to eq('name' => 'Vilso Tozi', 'lid' => nil, 'phone' => '5566999991234')
      end
    end

    context 'when the LID comes without a name' do
      let(:content) { "👥 *229480102662169@lid*\n\ntexto" }

      it 'extrai o LID e deixa o nome nulo' do
        expect(described_class.call(content).sender).to eq('name' => nil, 'lid' => '229480102662169', 'phone' => nil)
      end
    end

    context 'without any prefix (1:1 conversation, the normal case)' do
      it 'devolve o conteudo intacto e sem autor' do
        result = described_class.call('Bom dia, tudo certo?')

        expect(result.content).to eq('Bom dia, tudo certo?')
        expect(result.sender).to be_nil
        expect(result).not_to be_matched
      end

      it 'preserva nil' do
        result = described_class.call(nil)

        expect(result.content).to be_nil
        expect(result).not_to be_matched
      end

      it 'nao toca em texto que apenas contem o emoji no meio' do
        content = "Reuniao com o time 👥 *hoje*\n\nas 15h"
        expect(described_class.call(content).content).to eq(content)
      end
    end

    context 'when only the prefix arrives, with no body (attachment message)' do
      it 'trata o corpo com uma unica quebra de linha' do
        result = described_class.call("👥 *#{lrm}Rogerio José Da Silva (229480102662169@lid)*\n")

        expect(result.content).to be_nil
        expect(result.sender['name']).to eq('Rogerio José Da Silva')
      end

      it 'trata o corpo sem quebra de linha nenhuma' do
        result = described_class.call('👥 *Tecnologia (267722592149653@lid)*')

        expect(result.content).to be_nil
        expect(result.sender['lid']).to eq('267722592149653')
      end
    end

    context 'when the user text contains parentheses or asterisks' do
      it 'nao mutila o corpo' do
        body = "Ele disse *isso* (e mais (aninhado)) — ok?\nlinha 2 * com asterisco"
        result = described_class.call("👥 *Paulo Moggi (209417@lid)*\n\n#{body}")

        expect(result.content).to eq(body)
      end

      it 'nao mutila um corpo que por acaso cita um identificador' do
        body = 'olha o (229480102662169@lid) que apareceu'
        result = described_class.call("👥 *Paulo Moggi (209480102662169@lid)*\n\n#{body}")

        expect(result.content).to eq(body)
      end

      it 'preserva parenteses que fazem parte do nome' do
        result = described_class.call("👥 *Fulano (Suporte) (229480102662169@lid)*\n\noi")

        expect(result.sender['name']).to eq('Fulano (Suporte)')
        expect(result.sender['lid']).to eq('229480102662169')
      end
    end

    context 'with degenerate input' do
      it 'nao devolve autor quando o miolo e vazio' do
        result = described_class.call("👥 * *\n\ntexto")

        expect(result).to be_matched
        expect(result.sender).to be_nil
        expect(result.content).to eq('texto')
      end

      it 'devolve as tres chaves sempre presentes' do
        result = described_class.call("👥 *Angela*\n\noi")

        expect(result.sender.keys).to contain_exactly('name', 'lid', 'phone')
      end
    end
  end
end
