require 'rails_helper'

describe CustomAttributes::AutoProvisionService do
  subject(:service) { described_class }

  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }

  def definitions(model = 'contact_attribute')
    account.custom_attribute_definitions.where(attribute_model: model)
  end

  # `model` e posicional de proposito: com um keyword aqui, Ruby 3 leria
  # `provision('chave' => 1)` como kwargs e o posicional chegaria vazio.
  def provision(attributes, model = :contact_attribute)
    service.new(account: account, attribute_model: model, custom_attributes: attributes).perform
  end

  describe 'chave nova vinda do site' do
    it 'cria a definicao que faltava' do
      expect { provision('carrinho_valor' => 4200) }.to change(definitions, :count).by(1)

      definition = definitions.find_by(attribute_key: 'carrinho_valor')
      expect(definition.attribute_display_name).to eq('Carrinho valor')
      expect(definition.attribute_model).to eq('contact_attribute')
    end

    it 'nao cria de novo quando a chave ja tem definicao' do
      provision('carrinho_valor' => 4200)

      expect { provision('carrinho_valor' => 9999) }.not_to change(definitions, :count)
    end

    it 'provisiona so as chaves novas de um lote misto' do
      create(:custom_attribute_definition, account: account, attribute_key: 'plano',
                                           attribute_model: 'contact_attribute', attribute_display_type: 'text')

      expect { provision('plano' => 'pro', 'carrinho_valor' => 4200, 'cupom' => 'BLACK') }
        .to change(definitions, :count).by(2)
      expect(definitions.pluck(:attribute_key)).to contain_exactly('plano', 'carrinho_valor', 'cupom')
    end

    it 'infere o tipo a partir do primeiro valor visto' do
      provision('carrinho_valor' => 4200, 'cupom' => 'BLACK', 'assinante' => true)

      expect(definitions.find_by(attribute_key: 'carrinho_valor').attribute_display_type).to eq('number')
      expect(definitions.find_by(attribute_key: 'cupom').attribute_display_type).to eq('text')
      expect(definitions.find_by(attribute_key: 'assinante').attribute_display_type).to eq('checkbox')
    end

    it 'separa contato de conversa: sao modelos diferentes' do
      provision({ 'carrinho_valor' => 4200 }, :conversation_attribute)

      expect(definitions('contact_attribute').count).to eq(0)
      expect(definitions('conversation_attribute').pluck(:attribute_key)).to eq(['carrinho_valor'])
    end
  end

  # Aceite: chave reservada nao cria definicao NEM levanta erro. `email` e
  # `name` batem em attribute_must_not_conflict (custom_attribute_definition.rb:97)
  # e um create! cru levantaria RecordInvalid no meio da identificacao do contato.
  describe 'chaves que nao podem virar definicao' do
    it 'ignora chave reservada do contato, sem levantar' do
      reserved = %w[name email phone_number identifier country_code city company_name created_at last_activity_at referer blocked]

      expect { provision(reserved.index_with { |key| "valor de #{key}" }) }
        .not_to change(definitions, :count)
    end

    it 'ignora chave reservada da conversa, sem levantar' do
      reserved = %w[status priority assignee_id inbox_id team_id display_id campaign_id labels]

      expect { provision(reserved.index_with { 'x' }, :conversation_attribute) }
        .not_to change(definitions('conversation_attribute'), :count)
    end

    it 'ignora chave com formato que a definicao recusaria' do
      expect { provision('chave com espaco' => 1, 'chave/barra' => 2, 'acento é ok' => 3) }
        .not_to change(definitions, :count)
    end

    it 'aceita acento e digito, que o formato permite' do
      expect { provision('valor_pedido_2' => 10, 'código' => 'x') }.to change(definitions, :count).by(2)
    end

    it 'ignora chave em branco' do
      expect { provision('' => 'x', '   ' => 'y') }.not_to change(definitions, :count)
    end

    it 'ignora modelo de atributo desconhecido' do
      expect { provision({ 'carrinho_valor' => 1 }, :marciano_attribute) }
        .not_to change(CustomAttributeDefinition, :count)
    end

    it 'nao faz nada com payload vazio ou nulo' do
      expect { provision({}) }.not_to change(definitions, :count)
      expect { provision(nil) }.not_to change(definitions, :count)
    end
  end

  # Aceite: corrida cria uma definicao so. Quem garante e o indice unico
  # (attribute_key, attribute_model, account_id). A validacao de unicidade do
  # Rails nao ve o INSERT da outra requisicao antes do commit dela, entao a
  # corrida chega ao banco de duas formas — e as duas sao testadas aqui.
  #
  # Nao ha teste com threads de proposito: sob fixtures transacionais a conta
  # criada nesta transacao nao existe para outra conexao, entao um teste de
  # thread mediria a fixture, nao a corrida. Seria verde mentindo.
  describe 'corrida entre duas requisicoes' do
    it 'sobrevive quando a outra requisicao commitou entre o SELECT e o INSERT' do
      instance = service.new(account: account, attribute_model: :contact_attribute,
                             custom_attributes: { 'carrinho_valor' => 4200 })
      # Memoriza "esta chave nao existe" — e so entao a outra requisicao cria.
      instance.send(:provisionable)
      create(:custom_attribute_definition, account: account, attribute_key: 'carrinho_valor',
                                           attribute_model: 'contact_attribute', attribute_display_type: 'number')

      expect { instance.perform }.not_to raise_error
      expect(definitions.where(attribute_key: 'carrinho_valor').count).to eq(1)
    end

    it 'sobrevive ao INSERT recusado pelo indice unico, sem propagar o erro' do
      relation = account.custom_attribute_definitions
      allow(account).to receive(:custom_attribute_definitions).and_return(relation)
      allow(relation).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique.new('duplicate key value'))

      expect { provision('carrinho_valor' => 4200) }.not_to raise_error
      expect(definitions.where(attribute_key: 'carrinho_valor').count).to eq(0)
    end
  end

  # Aceite: "aparece no painel E VIRA FILTRAVEL". Filtravel nao e opiniao:
  # Filters::CustomAttributeFilterHelper#custom_attribute_query devolve string
  # VAZIA quando nao acha definicao (custom_attribute_filter_helper.rb:6), e
  # filters/filter_helper.rb:22-25 converte fragmento vazio em InvalidAttribute.
  describe 'vira filtravel de verdade' do
    let!(:alvo) { create(:contact, account: account, email: 'alvo@corp.com', custom_attributes: { 'carrinho_valor' => 4200 }) }
    let!(:outro) { create(:contact, account: account, email: 'outro@corp.com', custom_attributes: { 'carrinho_valor' => 10 }) }

    def filter_by_carrinho
      Contacts::FilterService.new(account, user, {
                                    payload: [{
                                      attribute_key: 'carrinho_valor',
                                      filter_operator: 'equal_to',
                                      values: [4200],
                                      query_operator: nil,
                                      custom_attribute_type: 'contact_attribute'
                                    }.with_indifferent_access]
                                  }).perform
    end

    it 'sem definicao o filtro recusa a chave inteira' do
      expect(definitions.find_by(attribute_key: 'carrinho_valor')).to be_nil

      # custom_attribute_query devolve '' sem definicao
      # (custom_attribute_filter_helper.rb:6), e filter_helper.rb:22-25 converte
      # fragmento vazio em InvalidAttribute. O agente que tentasse filtrar por
      # um dado que o site JA mandou recebia erro dizendo que a chave nao existe.
      expect { filter_by_carrinho }.to raise_error(CustomExceptions::CustomFilter::InvalidAttribute)
    end

    it 'depois de provisionar, o filtro separa o contato certo' do
      # `outro` tem a MESMA chave com outro valor: sem ele, um filtro que
      # casasse tudo passaria neste teste do mesmo jeito.
      expect(account.contacts.pluck(:id)).to contain_exactly(alvo.id, outro.id)

      provision('carrinho_valor' => 4200)

      result = filter_by_carrinho
      expect(result[:contacts].map(&:id)).to eq([alvo.id])
      expect(result[:count]).to eq(1)
    end
  end
end
