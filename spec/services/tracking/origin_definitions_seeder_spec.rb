require 'rails_helper'

RSpec.describe Tracking::OriginDefinitionsSeeder do
  let(:account) { create(:account) }

  def origin_definitions
    account.custom_attribute_definitions.where(attribute_key: Tracking::OriginAttributes.all_keys)
  end

  describe 'o estado ANTES do seed (o defeito que este bloco fecha)' do
    it 'não conhece nenhuma chave de origem, então nada dela apareceria no painel' do
      expect(origin_definitions.count).to eq(0)
    end
  end

  describe '#perform' do
    it 'cria exatamente as chaves do catálogo, nas duas superfícies' do
      described_class.new(account).perform

      conversation_keys = account.custom_attribute_definitions.where(attribute_model: 'conversation_attribute').pluck(:attribute_key)
      contact_keys = account.custom_attribute_definitions.where(attribute_model: 'contact_attribute').pluck(:attribute_key)

      expect(conversation_keys).to match_array(
        %w[last_utm_source last_utm_medium last_utm_campaign last_utm_term last_utm_content last_utm_id
           last_gclid last_gbraid last_wbraid last_fbclid last_msclkid last_ttclid
           last_referrer_host last_landing_path last_origin_kind]
      )
      expect(contact_keys).to match_array(
        %w[first_utm_source first_utm_medium first_utm_campaign first_utm_term first_utm_content first_utm_id
           first_referrer_host first_landing_path first_origin_kind]
      )
      expect(conversation_keys.size + contact_keys.size).to eq(24)
    end

    it 'grava o nome no idioma da conta e o tipo certo por chave' do
      account.update!(locale: 'pt_BR')
      described_class.new(account).perform

      source = account.custom_attribute_definitions.find_by(attribute_key: 'last_utm_source', attribute_model: 'conversation_attribute')
      kind = account.custom_attribute_definitions.find_by(attribute_key: 'last_origin_kind', attribute_model: 'conversation_attribute')

      expect(source.attribute_display_name).to eq('Origem da campanha (última)')
      expect(source.attribute_display_type).to eq('text')
      expect(kind.attribute_display_type).to eq('list')
      expect(kind.attribute_values).to eq(
        %w[busca_paga busca_organica social ia_generativa email referencia nao_disponivel]
      )
    end

    it 'usa o idioma da conta quando ela é en' do
      account.update!(locale: 'en')
      described_class.new(account).perform

      expect(account.custom_attribute_definitions.find_by(attribute_key: 'last_utm_source').attribute_display_name)
        .to eq('Campaign source (last)')
    end

    it 'nunca oferece "origem direta" como valor — ausência de dado é nao_disponivel' do
      described_class.new(account).perform
      values = account.custom_attribute_definitions.find_by(attribute_key: 'last_origin_kind').attribute_values

      expect(values).to include('nao_disponivel')
      expect(values).not_to include('direta', 'direct')
    end

    describe 'idempotência — o aceite do bloco' do
      it 'rodar duas vezes não duplica nem levanta' do
        described_class.new(account).perform
        depois_da_primeira = origin_definitions.count

        expect { described_class.new(account).perform }.not_to raise_error

        expect(depois_da_primeira).to eq(24)
        expect(origin_definitions.count).to eq(24)
      end

      it 'a segunda passagem não cria nada (o retorno mede isso, não o count)' do
        expect(described_class.new(account).perform.size).to eq(24)
        expect(described_class.new(account).perform).to eq([])
      end

      it 'preserva a curadoria do cliente em vez de reescrever o nome' do
        described_class.new(account).perform
        definicao = account.custom_attribute_definitions.find_by(attribute_key: 'last_utm_source')
        definicao.update!(attribute_display_name: 'Fonte do lead', attribute_description: 'renomeado pelo cliente')

        described_class.new(account).perform

        expect(definicao.reload.attribute_display_name).to eq('Fonte do lead')
        expect(definicao.attribute_description).to eq('renomeado pelo cliente')
      end

      it 'completa o que falta quando uma definição foi apagada' do
        described_class.new(account).perform
        account.custom_attribute_definitions.find_by(attribute_key: 'last_gclid').destroy!

        criadas = described_class.new(account).perform

        expect(criadas.map(&:attribute_key)).to eq(['last_gclid'])
        expect(origin_definitions.count).to eq(24)
      end
    end

    it 'na corrida, o índice único decide e o serviço não estoura' do
      # Injeção de falha, não espelho da implementação: as definições JÁ existem no banco (a
      # outra requisição ganhou), mas esta instância enxerga o mundo vazio — que é exatamente o
      # que acontece quando as duas leem antes de qualquer uma gravar. O que se verifica é o
      # efeito: não estoura, e continua havendo UMA definição por chave.
      described_class.new(account).perform
      seeder = described_class.new(account)
      allow(seeder).to receive(:existing_keys).and_return(Set.new)

      expect { seeder.perform }.not_to raise_error

      expect(account.custom_attribute_definitions.where(attribute_key: 'last_utm_source').count).to eq(1)
      expect(origin_definitions.count).to eq(24)
    end

    it 'nenhuma chave do catálogo colide com atributo padrão do Chatwoot' do
      padrao = CustomAttributeDefinition::STANDARD_ATTRIBUTES.values.flatten
      expect(Tracking::OriginAttributes.all_keys & padrao).to eq([])
    end

    it 'toda chave do catálogo passa no formato aceito pelo modelo' do
      expect(described_class.new(account).perform.all?(&:persisted?)).to be(true)
    end
  end
end
