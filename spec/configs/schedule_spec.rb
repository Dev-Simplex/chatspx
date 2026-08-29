## we had instances where after copy pasting the schedule block,
## the dev forgets to changes the schedule key,
## this would break some of the scheduled jobs with out explicit errors
require 'rails_helper'

RSpec.context 'with valid schedule.yml' do
  it 'does not have duplicates' do
    file = Rails.root.join('config/schedule.yml')
    schedule_keys = []
    invalid_line_starts = [' ', '#', "\n"]
    # couldn't figure out a proper solution with yaml.parse
    # so the rudementary solution is to read the file and parse it
    # check for duplicates in the array
    File.open(file).each do |f|
      f.each_line do |line|
        next if invalid_line_starts.include?(line[0])

        schedule_keys << line.split(':')[0]
      end
    end
    # ensure that no duplicates exist
    expect(schedule_keys.count).to eq(schedule_keys.uniq.count)
  end

  # A entrada existir nao basta: ela tem de APONTAR para uma classe que existe. O sidekiq-cron
  # carrega o arquivo e, com um nome que nao resolve, o job simplesmente nunca roda — sem erro
  # de boot e sem nada vermelho. E a mesma classe de defeito do bloco 4.14 (job escrito, cron
  # ausente) vista pelo outro lado: cron presente, classe ausente. Medido: trocar UMA linha por
  # um nome inexistente derruba este exemplo, nomeando a chave.
  it 'aponta apenas para classes que existem' do
    schedule = YAML.load_file(Rails.root.join('config/schedule.yml'))

    orfas = schedule.filter_map do |key, entry|
      klass = entry['class']
      next if klass.blank?

      key unless klass.safe_constantize
    end

    expect(orfas).to be_empty, "entradas de schedule.yml sem classe: #{orfas.join(', ')}"
  end
end
