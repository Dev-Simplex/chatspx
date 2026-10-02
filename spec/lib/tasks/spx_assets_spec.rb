require 'spec_helper'
require 'rake'
require 'tmpdir'
require 'pathname'
require 'rails'

describe 'spx:assets:verificar_producao' do # rubocop:disable RSpec/DescribeClass
  let(:root) { Pathname.new(Dir.mktmpdir) }

  around do |example|
    original_application = Rake.application
    Rake.application = Rake::Application.new
    example.run
  ensure
    Rake.application = original_application
    FileUtils.remove_entry(root)
  end

  before do
    allow(Rails).to receive(:public_path).and_return(root.join('public'))
    FileUtils.mkdir_p(root.join('public/vite/assets'))
    load File.expand_path('../../../lib/tasks/spx_assets.rake', __dir__)
  end

  def write_asset(content)
    File.write(root.join('public/vite/assets/app.js'), content)
  end

  it 'falha quando encontra o aviso de desenvolvimento do Vue' do
    write_asset('console.warn("Extraneous non-props attributes");')

    expect { Rake::Task['spx:assets:verificar_producao'].invoke }.to raise_error(SystemExit, /Assets com código de desenvolvimento/)
  end

  it 'aprova assets de produção mesmo com a compatibilidade do Sentry' do
    write_asset('console.error("[Vue warn]: erro capturado pelo Sentry");')

    expect { Rake::Task['spx:assets:verificar_producao'].invoke }.to output(/Verificação de produção OK/).to_stdout
  end

  it 'falha quando o build não gerou assets' do
    expect { Rake::Task['spx:assets:verificar_producao'].invoke }.to raise_error(SystemExit, /Nenhum asset JavaScript encontrado/)
  end
end
