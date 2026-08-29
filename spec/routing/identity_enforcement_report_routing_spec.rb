require 'rails_helper'

# A armadilha singular/plural precisa ser medida no ROTEADOR, nao pela resposta: sem rota,
# tanto o caminho certo quanto o errado devolvem 404, e um spec de request nao distingue
# "a rota nao existe" de "a inbox nao existe". `be_routable` so existe em `type: :routing`.
RSpec.describe 'relatorio de enforcement de identidade — singular x plural', type: :routing do
  it 'roteia GET no caminho SINGULAR — o que o Rails serve' do
    expect(get: '/api/v1/accounts/1/inboxes/2/identity_enforcement_report').to be_routable
  end

  # O espelho da assercao acima. Sozinha, a negativa passaria tambem se a rota tivesse sido
  # escrita no plural — e e exatamente essa a troca que ja custou 404 no 5.02.
  it 'o caminho PLURAL nao existe — trocar um pelo outro reproduz o 404 uniforme' do
    expect(get: '/api/v1/accounts/1/inboxes/2/identity_enforcement_reports').not_to be_routable
  end

  it 'roteia para o controller PLURAL, que e como o Rails resolve `resource` singular' do
    expect(get: '/api/v1/accounts/1/inboxes/2/identity_enforcement_report')
      .to route_to(controller: 'api/v1/accounts/inboxes/identity_enforcement_reports',
                   action: 'show', account_id: '1', inbox_id: '2', format: 'json')
  end
end
