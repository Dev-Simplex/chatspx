namespace :captain do
  desc 'Cria/sincroniza o AgentBot-espelho de todos os Captain::Assistant'
  task sync_mirrors: :environment do
    Captain::Assistant.find_each { |a| Captain::AssistantMirrorService.new(a).sync! }
  end
end
