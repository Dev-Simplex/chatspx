require 'spec_helper'
require 'rake'
require 'rails'
require 'climate_control'

describe 'before_assets_precompile' do # rubocop:disable RSpec/DescribeClass
  let(:task_context) { Rake::Task['before_assets_precompile'].actions.first.binding.receiver }

  around do |example|
    original_application = Rake.application
    Rake.application = Rake::Application.new
    with_modified_env(NODE_ENV: 'development') { example.run }
  ensure
    Rake.application = original_application
  end

  before do
    Rake::Task.define_task(:environment)
    Rake::Task.define_task('assets:precompile')
    load File.expand_path('../../../lib/tasks/build.rake', __dir__)
    allow(task_context).to receive(:system).and_return(true)
  end

  it 'força produção antes de executar os comandos do frontend' do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
    node_environments = []
    allow(task_context).to receive(:system) { node_environments << ENV.fetch('NODE_ENV') }

    Rake::Task['assets:precompile'].invoke

    expect(node_environments).to all(eq('production'))
    expect(node_environments).not_to be_empty
  end

  it 'preserva o ambiente Node fora de produção' do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))

    Rake::Task['assets:precompile'].invoke

    expect(ENV.fetch('NODE_ENV')).to eq('development')
  end
end
