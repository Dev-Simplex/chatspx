require 'rails_helper'

# A versao do produto e declarada em DOIS lugares que ninguem obriga a concordar:
#
#   · `package.json`  — o que o upstream bump na tag, e o que o front carrega;
#   · `config/app.yml` — o que o Rails ANUNCIA: `/api`, `APP_VERSION` no
#     dashboard, o painel do super_admin e o `installation_version` que o
#     `ChatwootHub` reporta para fora.
#
# No merge da v4.16.2 os dois divergiram: `package.json` foi para 4.16.2 e
# `config/app.yml` ficou em 4.12.1, e a instalacao passou meses anunciando uma
# versao que nao era a que rodava — inclusive para o Hub.
#
# O spec de `/api` que ja existia nao pega isso: ele compara a resposta com
# `Chatwoot.config[:version]`, ou seja, a fonte consigo mesma. Passa com
# QUALQUER valor. Este aqui compara as duas fontes independentes, que e a unica
# forma de a divergencia aparecer.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Paridade de versao entre package.json e config/app.yml' do
  # rubocop:enable RSpec/DescribeClass
  let(:package_json_version) do
    JSON.parse(Rails.root.join('package.json').read).fetch('version')
  end

  it 'anuncia no Rails a mesma versao declarada no package.json' do
    expect(Chatwoot.config[:version]).to eq(package_json_version)
  end

  it 'declara a versao no formato semantico, sem prefixo' do
    expect(Chatwoot.config[:version]).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
