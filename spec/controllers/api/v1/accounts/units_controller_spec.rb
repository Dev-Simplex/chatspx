# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Units API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/units" }

  describe 'sem autenticação' do
    it 'recusa' do
      get base

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET index' do
    # O furo que o checkup achou: sem `Scope` própria a policy devolvia a tabela
    # inteira, e a lista mostrava unidade de qualquer conta da instância.
    it 'devolve só as unidades da conta corrente' do
      minha = create(:unit, account: account, name: 'Sinop')
      alheia = create(:unit, account: create(:account), name: 'De outra conta')

      get base, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      ids = response.parsed_body.map { |u| u['id'] }
      expect(ids).to contain_exactly(minha.id)
      expect(ids).not_to include(alheia.id)
    end

    it 'o agente também lê a lista — ver horário de filial é trabalho de atendimento' do
      create(:unit, account: account)

      get base, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'traz a grade da semana e as regras de agenda no payload' do
      unidade = create(:unit, account: account)
      create(:unit_exception, unit: unidade, name: 'Natal', frequency: :anual)

      get base, headers: admin.create_new_auth_token, as: :json

      corpo = response.parsed_body.first
      expect(corpo['working_hours'].size).to eq(7)
      expect(corpo['exceptions'].first).to include('name' => 'Natal', 'frequency' => 'anual')
      expect(corpo['working_hours'].first).to have_key('break_start_hour')
    end
  end

  describe 'unidade de outra conta' do
    let(:alheia) { create(:unit, account: create(:account)) }

    it 'não deixa ler, editar nem apagar trocando o id na URL' do
      cabecalho = admin.create_new_auth_token

      get "#{base}/#{alheia.id}", headers: cabecalho, as: :json
      expect(response).to have_http_status(:not_found)

      patch "#{base}/#{alheia.id}", params: { unit: { name: 'Invadida' } }, headers: cabecalho, as: :json
      expect(response).to have_http_status(:not_found)

      delete "#{base}/#{alheia.id}", headers: cabecalho, as: :json
      expect(response).to have_http_status(:not_found)
      expect(alheia.reload).to be_persisted
    end
  end

  describe 'permissões de escrita' do
    it 'agente não cria, não edita e não apaga' do
      unidade = create(:unit, account: account)
      cabecalho = agent.create_new_auth_token

      post base, params: { unit: { name: 'Nova', timezone: 'America/Cuiaba' } }, headers: cabecalho, as: :json
      expect(response).to have_http_status(:unauthorized)

      patch "#{base}/#{unidade.id}", params: { unit: { name: 'Editada' } }, headers: cabecalho, as: :json
      expect(response).to have_http_status(:unauthorized)

      delete "#{base}/#{unidade.id}", headers: cabecalho, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(unidade.reload.name).not_to eq('Editada')
    end
  end

  describe 'POST create' do
    # O numero da casa precisa ser aceito no permit E devolvido no jbuilder: campo que grava mas nao
    # volta some na proxima edicao (foi o que aconteceu com o applies_to_inboxes).
    it 'guarda o numero do endereco e devolve na resposta' do
      post base,
           params: { unit: { name: 'Com numero', address: 'Rua dos Papiros - Centro', address_number: 'S/N' } },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(account.units.find_by(name: 'Com numero').address_number).to eq('S/N')
      expect(response.parsed_body['address_number']).to eq('S/N')
    end

    it 'cria com a grade que a tela manda, as regras e as caixas' do
      caixa = create(:inbox, account: account)

      post base,
           params: { unit: {
             name: 'Sinop', city: 'Sinop', state: 'MT', timezone: 'America/Cuiaba',
             inbox_ids: [caixa.id],
             working_hours_attributes: [
               { day_of_week: 0, closed_all_day: true },
               { day_of_week: 1, closed_all_day: false, open_hour: 8, open_minutes: 0, close_hour: 18, close_minutes: 0,
                 break_start_hour: 12, break_start_minutes: 0, break_end_hour: 13, break_end_minutes: 30 }
             ],
             exceptions: [
               { starts_on: '2026-12-25', name: 'Natal', category: 'feriado', frequency: 'anual', closed_all_day: true },
               { starts_on: '2026-09-01', name: 'Plantão', category: 'evento', frequency: 'mensal',
                 weekdays: [0], week_positions: [1, 3], closed_all_day: false,
                 open_hour: 8, open_minutes: 0, close_hour: 12, close_minutes: 0 }
             ]
           } },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      unidade = account.units.find_by(name: 'Sinop')
      expect(unidade.working_hours.count).to eq(2)
      expect(unidade.working_hours.find_by(day_of_week: 1).break_end_hour).to eq(13)
      expect(unidade.exceptions.where(name: %w[Natal Plantão]).pluck(:frequency)).to contain_exactly('anual', 'mensal')
      expect(caixa.reload.unit_id).to eq(unidade.id)
    end

    # O calendário não nasce vazio: os feriados nacionais entram no mesmo request, e o dia que a
    # tela já marcou não ganha um segundo feriado em cima.
    it 'traz os feriados nacionais junto, sem repetir o que a tela mandou' do
      post base,
           params: { unit: {
             name: 'Sorriso', timezone: 'America/Cuiaba',
             exceptions: [
               { starts_on: '2026-12-25', name: 'Natal', category: 'feriado', frequency: 'anual',
                 closed_all_day: true }
             ]
           } },
           headers: admin.create_new_auth_token, as: :json

      unidade = account.units.find_by(name: 'Sorriso')
      expect(unidade.exceptions.pluck(:name)).to include('Tiradentes', 'Carnaval')
      expect(unidade.exceptions.where(name: 'Natal').count).to eq(1)
      expect(unidade.feriados_nacionais_ate).to eq(Date.current.year + 4)
    end

    # Antes da transação, a unidade ficava gravada pela metade depois do erro.
    it 'não deixa unidade meio criada quando uma regra é inválida' do
      expect do
        post base,
             params: { unit: {
               name: 'Vai falhar', timezone: 'America/Cuiaba',
               exceptions: [{ starts_on: '2026-09-01', name: 'Sem dia', frequency: 'semanal', weekdays: [] }]
             } },
             headers: admin.create_new_auth_token, as: :json
      end.not_to change(Unit, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'ignora caixa de outra conta' do
      caixa_alheia = create(:inbox, account: create(:account))

      post base, params: { unit: { name: 'Com caixa alheia', timezone: 'UTC', inbox_ids: [caixa_alheia.id] } },
                 headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(caixa_alheia.reload.unit_id).to be_nil
    end
  end

  describe 'PATCH update' do
    let(:unidade) { create(:unit, account: account, name: 'Sinop') }

    it 'substitui o conjunto de regras inteiro' do
      create(:unit_exception, unit: unidade, name: 'Antiga')

      patch "#{base}/#{unidade.id}",
            params: { unit: { name: 'Sinop Centro',
                              exceptions: [{ starts_on: '2026-11-15', name: 'Nova', closed_all_day: true }] } },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(unidade.reload.name).to eq('Sinop Centro')
      expect(unidade.exceptions.pluck(:name)).to contain_exactly('Nova')
    end

    it 'lista vazia apaga todas as regras' do
      create(:unit_exception, unit: unidade)

      patch "#{base}/#{unidade.id}", params: { unit: { exceptions: [] } },
                                     headers: admin.create_new_auth_token, as: :json

      expect(unidade.reload.exceptions).to be_empty
    end

    it 'chave ausente não mexe nas regras' do
      create(:unit_exception, unit: unidade, name: 'Fica')

      patch "#{base}/#{unidade.id}", params: { unit: { name: 'Só o nome' } },
                                     headers: admin.create_new_auth_token, as: :json

      expect(unidade.reload.exceptions.pluck(:name)).to contain_exactly('Fica')
    end

    # O destroy_all acontecia fora da transação: o usuário via 422 E perdia o que tinha.
    it 'não perde as regras antigas quando a nova é inválida' do
      create(:unit_exception, unit: unidade, name: 'Natal')

      patch "#{base}/#{unidade.id}",
            params: { unit: { exceptions: [{ starts_on: '2026-09-01', name: 'Inválida', frequency: 'mensal' }] } },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(unidade.reload.exceptions.pluck(:name)).to contain_exactly('Natal')
    end

    it 'desvincula a caixa que saiu da unidade' do
      caixa = create(:inbox, account: account)
      caixa.update!(unit_id: unidade.id)

      patch "#{base}/#{unidade.id}", params: { unit: { inbox_ids: [] } },
                                     headers: admin.create_new_auth_token, as: :json

      expect(caixa.reload.unit_id).to be_nil
    end
  end

  describe 'DELETE destroy' do
    it 'apaga a unidade e solta a caixa' do
      unidade = create(:unit, account: account)
      caixa = create(:inbox, account: account)
      caixa.update!(unit_id: unidade.id)

      delete "#{base}/#{unidade.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(Unit.find_by(id: unidade.id)).to be_nil
      expect(caixa.reload.unit_id).to be_nil
    end
  end

  # As condições de atendimento da unidade (retirada, exigência de documento, o que o ramo pedir).
  # A ferramenta da IA já as lia; sem estar nos strong params, o time não tinha como cadastrá-las
  # a não ser por console — então o campo existia e ninguém alcançava.
  describe 'condições de atendimento' do
    it 'grava as condições que a tela manda' do
      cabecalho = admin.create_new_auth_token

      post base,
           params: { unit: { name: 'Matriz', timezone: 'America/Cuiaba',
                             atributos: { 'retirada de chaves' => 'até as 16h30' } } },
           headers: cabecalho, as: :json

      expect(response).to have_http_status(:success)
      expect(Unit.last.atributos).to eq('retirada de chaves' => 'até as 16h30')
    end

    it 'substitui o conjunto ao editar — remover linha na tela remove a condição' do
      cabecalho = admin.create_new_auth_token
      unidade = create(:unit, account: account, atributos: { 'a' => '1', 'b' => '2' })

      patch "#{base}/#{unidade.id}", params: { unit: { atributos: { 'a' => '1' } } },
                                     headers: cabecalho, as: :json

      expect(response).to have_http_status(:success)
      expect(unidade.reload.atributos).to eq('a' => '1')
    end

    it 'não mexe nas condições quando a chave não vem' do
      cabecalho = admin.create_new_auth_token
      unidade = create(:unit, account: account, atributos: { 'a' => '1' })

      patch "#{base}/#{unidade.id}", params: { unit: { name: 'Outro nome' } },
                                     headers: cabecalho, as: :json

      expect(unidade.reload.atributos).to eq('a' => '1')
    end
  end

  # O papel de cada caixa e se ela é canal de destino (InboxCanal). A tela de unidades grava e lê
  # pelo mesmo `canais`, então o ciclo salvar -> ler precisa fechar.
  describe 'canal de cada caixa' do
    let(:unidade) { create(:unit, account: account) }
    let(:whatsapp) do
      create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox.tap do |caixa|
        caixa.update!(unit_id: unidade.id)
      end
    end
    let(:site) { create(:inbox, account: account).tap { |caixa| caixa.update!(unit_id: unidade.id) } }

    def gravar(canais)
      patch "#{base}/#{unidade.id}", params: { unit: { canais: canais } }, headers: admin.create_new_auth_token, as: :json
    end

    it 'grava o papel, o destino e o template, e devolve na leitura' do
      gravar([{ inbox_id: whatsapp.id, papel: ' Atendimento geral ', destino: true, principal: true,
                template_name: 'acionamento', template_language: 'pt_BR' }])

      expect(response).to have_http_status(:success)
      expect(whatsapp.reload.canal_config).to eq('papel' => 'Atendimento geral', 'destino' => true, 'principal' => true,
                                                 'template_name' => 'acionamento', 'template_language' => 'pt_BR')
      devolvido = response.parsed_body['canais'].find { |canal| canal['inbox_id'] == whatsapp.id }
      expect(devolvido).to include('papel' => 'Atendimento geral', 'destino' => true, 'template_name' => 'acionamento')
    end

    it 'preserva os outros atributos da caixa' do
      whatsapp.update!(additional_attributes: { 'pin_mode' => 'per_inbox' })

      gravar([{ inbox_id: whatsapp.id, papel: 'Vendas' }])

      canal = { 'papel' => 'Vendas', 'destino' => false, 'principal' => false }
      expect(whatsapp.reload.additional_attributes).to include('pin_mode' => 'per_inbox', 'canal' => canal)
    end

    it 'ignora caixa que não é da unidade' do
      alheia = create(:inbox, account: account)

      gravar([{ inbox_id: alheia.id, papel: 'Intrusa' }])

      expect(response).to have_http_status(:success)
      expect(alheia.reload.papel).to be_nil
    end

    it 'não mexe quando a chave não vem' do
      whatsapp.update!(canal: { 'papel' => 'Vendas' })

      patch "#{base}/#{unidade.id}", params: { unit: { name: 'Outro nome' } }, headers: admin.create_new_auth_token, as: :json

      expect(whatsapp.reload.papel).to eq('Vendas')
    end

    it 'recusa destino em caixa que não fala WhatsApp' do
      gravar([{ inbox_id: site.id, papel: 'Site', destino: true }])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(site.reload.canal_destino?).to be(false)
    end

    it 'recusa dois WhatsApp principais na mesma unidade, sem gravar nenhum' do
      outro = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
      outro.update!(unit_id: unidade.id)

      gravar([{ inbox_id: whatsapp.id, principal: true }, { inbox_id: outro.id, principal: true }])

      expect(response).to have_http_status(:unprocessable_entity)
      expect([whatsapp.reload, outro.reload].map(&:whatsapp_principal?)).to eq([false, false])
    end
  end
end
