# -*- coding: utf-8 -*-
# Build/geocoding do gazetteer de Sinop -> config['gazetteer'] da conta Tozi.
#
# DRY-RUN: le o acervo Vista (bairros distintos + centroide dos imoveis) + o gazetteer
# de pesquisa, concilia os dois, e GERA (sem gravar no banco) o subconjunto compacto
# pro config['gazetteer'] + um relatorio de reconciliacao. O apply na conta 6 e passo
# separado (ver rodape).
#
# Uso na VM (dentro do repo, branch com o gazetteer-sinop.json presente):
#   bundle exec rails runner scripts/spx/tozi/build_gazetteer_config.rb
#
# ENV opcionais:
#   GAZ_JSON  -> caminho do gazetteer-sinop.json (default: docs/clientes/tozi/…)
#   OUT_DIR   -> onde escrever as saidas (default: /tmp)
#   TOZI_VISTA_BASE_URL / TOZI_VISTA_API_KEY -> ja no ENV de producao
#
# Saidas: <OUT_DIR>/config-gazetteer-conta6.json  +  <OUT_DIR>/geocoding-reconciliacao.md

require 'json'
require 'httparty'
require 'fileutils'

GAZ_PATH   = ENV.fetch('GAZ_JSON', Rails.root.join('docs/clientes/tozi/gazetteer-sinop.json').to_s)
OUT_DIR    = ENV.fetch('OUT_DIR', '/tmp')
VISTA_BASE = ENV.fetch('TOZI_VISTA_BASE_URL', 'https://toz19328-rest.vistahost.com.br')
VISTA_KEY  = ENV['TOZI_VISTA_API_KEY'].to_s

# Ancora "central" = escritorio da Tozi (Centro), das coords da EnviarLocalizacaoTool.
CITY_LAT = -11.8519937
CITY_LNG = -55.5093314
CENTRAL_RAIO = 0.015 # ~1,6 km em lat; usado pra classificar o miolo

abort '[abort] TOZI_VISTA_API_KEY ausente no ENV' if VISTA_KEY.empty?
abort "[abort] gazetteer nao encontrado em #{GAZ_PATH}" unless File.exist?(GAZ_PATH)
FileUtils.mkdir_p(OUT_DIR)

def norm(str)
  str.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.gsub(/\s+/, ' ').strip
end

META_KEYS = %w[total paginas pagina quantidade].freeze

# 1) Puxa TODO o acervo de Sinop, paginando.
def fetch_all_imoveis
  fields = %w[Codigo Bairro BairroComercial Cidade Latitude Longitude Status]
  out = []
  page = 1
  loop do
    pesquisa = { fields: fields, filter: { 'Cidade' => 'Sinop' },
                 paginacao: { pagina: page, quantidade: 50 } }
    resp = HTTParty.get("#{VISTA_BASE}/imoveis/listar",
                        query: { key: VISTA_KEY, showtotal: 1, pesquisa: pesquisa.to_json },
                        headers: { 'Accept' => 'application/json' }, timeout: 30)
    break unless resp.code == 200

    data = resp.parsed_response
    data = JSON.parse(data) if data.is_a?(String)
    break unless data.is_a?(Hash)

    total_pages = data['paginas'].to_i
    registros = data.reject { |k, _| META_KEYS.include?(k) }.values.select { |v| v.is_a?(Hash) }
    out.concat(registros)
    page += 1
    break if registros.empty?
    break if total_pages.positive? && page > total_pages
    break if page > 60 # trava de seguranca
  end
  out
end

# 2) Agrega por bairro (prefere BairroComercial, como o buscar_imovel exibe/linka).
def aggregate(imoveis)
  by = Hash.new { |h, k| h[k] = { nome: nil, coords: [], total: 0, venda: 0, locacao: 0 } }
  imoveis.each do |im|
    nome = im['BairroComercial'].to_s.strip
    nome = im['Bairro'].to_s.strip if nome.empty?
    next if nome.empty?

    b = by[norm(nome)]
    b[:nome] ||= nome
    b[:total] += 1
    st = im['Status'].to_s.downcase
    b[:venda]   += 1 if st.include?('vend')
    b[:locacao] += 1 if st.include?('alug')
    lat = im['Latitude'].to_f
    lng = im['Longitude'].to_f
    b[:coords] << [lat, lng] unless lat.zero? && lng.zero?
  end
  by
end

def centroid(coords)
  return nil if coords.empty?

  [(coords.sum { |c| c[0] } / coords.size).round(6), (coords.sum { |c| c[1] } / coords.size).round(6)]
end

# Regiao data-driven a partir do centroide relativo a ancora central.
def regiao_por_centroide(lat, lng)
  return nil if lat.nil?

  dlat = lat - CITY_LAT # +norte
  dlng = lng - CITY_LNG # +leste
  return 'Central' if dlat.abs < CENTRAL_RAIO && dlng.abs < CENTRAL_RAIO

  ns = dlat >= 0 ? 'Norte' : 'Sul'
  lo = dlng >= 0 ? 'Leste' : 'Oeste'
  return ns if dlat.abs >= dlng.abs * 1.5
  return lo if dlng.abs >= dlat.abs * 1.5

  "#{ns}/#{lo}"
end

# ---- pipeline ----
puts '[1/4] Puxando acervo Vista (Sinop)...'
imoveis = fetch_all_imoveis
abort '[abort] Vista nao retornou imoveis — checar chave/endpoint.' if imoveis.empty?
puts "      #{imoveis.size} imoveis."

puts '[2/4] Agregando por bairro + centroide...'
agg = aggregate(imoveis)
puts "      #{agg.size} bairros distintos no acervo."

puts '[3/4] Conciliando com o gazetteer de pesquisa...'
gaz = JSON.parse(File.read(GAZ_PATH))
gaz_bairros = gaz['bairros'] || []
gaz_index = {}
gaz_bairros.each { |b| gaz_index[norm(b['nome'])] = b }

records = []
conflitos = []
long_tail_posicionado = []
vista_sem_perfil = []

# a) bairros COM imovel (espinha comercial) — ganham centroide + contagem reais
agg.each_value do |b|
  cen = centroid(b[:coords])
  reg_data = cen ? regiao_por_centroide(*cen) : nil
  g = gaz_index[norm(b[:nome])]

  rec = {
    'nome' => (g && g['nome']) || b[:nome],
    'regiao' => reg_data || (g && g['regiao']),
    'perfil' => g && g['perfil'],
    'faixa' => g && g['faixa_valor'],
    'avenidas' => (g && g['avenidas_principais']) || [],
    'perto' => (g && g['pontos_referencia_proximos']) || [],
    'vizinhos' => (g && g['bairros_vizinhos']) || [],
    'centroide' => cen ? { 'lat' => cen[0], 'lng' => cen[1] } : nil,
    'imoveis' => { 'total' => b[:total], 'venda' => b[:venda], 'locacao' => b[:locacao] },
    'geo_amostra' => b[:coords].size,
    'fonte' => g ? 'vista+gazetteer' : 'vista'
  }
  records << rec

  vista_sem_perfil << rec if g.nil?
  if g && g['regiao'].to_s.strip.present? && reg_data && norm(g['regiao']) != norm(reg_data)
    conflitos << { nome: rec['nome'], gazetteer: g['regiao'], dados: reg_data, n: b[:total] }
  end
  if g && cen && (g['regiao'].to_s.match?(/confirmar/i) || g['confianca'].to_s == 'baixa')
    long_tail_posicionado << { nome: rec['nome'], regiao: reg_data, n: b[:total] }
  end
end

# b) bairros do gazetteer SEM imovel no Vista (conhecimento puro)
sem_imovel = gaz_bairros.reject { |g| agg.key?(norm(g['nome'])) }
sem_imovel.each do |g|
  records << {
    'nome' => g['nome'],
    'regiao' => g['regiao'],
    'perfil' => g['perfil'],
    'faixa' => g['faixa_valor'],
    'avenidas' => g['avenidas_principais'] || [],
    'perto' => g['pontos_referencia_proximos'] || [],
    'vizinhos' => g['bairros_vizinhos'] || [],
    'centroide' => nil,
    'imoveis' => { 'total' => 0, 'venda' => 0, 'locacao' => 0 },
    'geo_amostra' => 0,
    'fonte' => 'gazetteer'
  }
end

# pontos de referencia: do gazetteer, sem o lixo de portal/online
pontos = (gaz['pontos_referencia'] || []).reject do |p|
  cat = p['categoria'].to_s.downcase
  cat.match?(/portal|classificad|agregador|imobili/) || p['regiao'].to_s.casecmp('nacional').zero?
end.map { |p| { 'nome' => p['nome'], 'categoria' => p['categoria'], 'regiao' => p['regiao'], 'bairro' => p['bairro'] } }

config = {
  'cidade' => 'Sinop/MT',
  'atualizado_em' => Time.now.strftime('%Y-%m-%d %H:%M %Z'),
  'ancora_central' => { 'lat' => CITY_LAT, 'lng' => CITY_LNG },
  'bairros' => records.sort_by { |r| -r['imoveis']['total'] },
  'pontos' => pontos
}

puts '[4/4] Escrevendo saidas...'
cfg_path = File.join(OUT_DIR, 'config-gazetteer-conta6.json')
File.write(cfg_path, JSON.pretty_generate(config))

# ---- relatorio ----
r = []
r << '# Geocoding do gazetteer — reconciliacao Vista x pesquisa'
r << ''
r << "- Imoveis no acervo (Sinop): **#{imoveis.size}**"
r << "- Bairros distintos no acervo: **#{agg.size}**"
r << "- Bairros do acervo COM perfil no gazetteer: **#{agg.size - vista_sem_perfil.size}**"
r << "- Bairros do acervo SEM perfil no gazetteer: **#{vista_sem_perfil.size}**"
r << "- Bairros so no gazetteer (sem imovel hoje): **#{sem_imovel.size}**"
r << "- Conflitos de regiao (gazetteer x dados): **#{conflitos.size}**"
r << "- Long-tail agora posicionado por centroide: **#{long_tail_posicionado.size}**"
r << "- Total de registros no config: **#{records.size}**  |  pontos: **#{pontos.size}**"
r << ''
r << '## Conflitos de regiao (gazetteer disse X, centroide diz Y) — checar'
r << '| Bairro | Gazetteer | Dados (centroide) | Imoveis |'
r << '|---|---|---|---|'
conflitos.sort_by { |c| -c[:n] }.each { |c| r << "| #{c[:nome]} | #{c[:gazetteer]} | #{c[:dados]} | #{c[:n]} |" }
r << ''
r << '## Bairros do acervo SEM perfil no gazetteer (tem imovel — precisam de perfil)'
vista_sem_perfil.sort_by { |x| -x['imoveis']['total'] }.each do |x|
  r << "- **#{x['nome']}** — regiao(dados): #{x['regiao'] || '?'} · #{x['imoveis']['total']} imoveis (#{x['geo_amostra']} c/ geo)"
end
r << ''
r << '## Long-tail agora posicionado (tinha regiao fraca; centroide resolveu)'
long_tail_posicionado.sort_by { |x| -x[:n] }.each { |x| r << "- #{x[:nome]} -> #{x[:regiao]} (#{x[:n]} imoveis)" }
r << ''
r << '## So no gazetteer (conhecimento, sem imovel hoje)'
r << sem_imovel.map { |g| g['nome'] }.sort.join(' · ')
r << ''

rep_path = File.join(OUT_DIR, 'geocoding-reconciliacao.md')
File.write(rep_path, r.join("\n"))

puts ''
puts "OK. config -> #{cfg_path}"
puts "    report -> #{rep_path}"
puts "Registros: #{records.size} bairros (#{agg.size} c/ imovel, #{sem_imovel.size} so-conhecimento), #{pontos.size} pontos."
puts "Conflitos de regiao: #{conflitos.size} | Vista sem perfil: #{vista_sem_perfil.size}"

# ============================================================================
# APPLY (passo SEPARADO — so com OK do Paulo, na conta 6, dentro da cerimonia):
#   1) achar o assistant certo (o que tem buscar_imovel):
#        bundle exec rails runner "pp Captain::Assistant.where(account_id:6).pluck(:id,:name)"
#   2) mesclar no config SEM clobber (preserva instructions/behavior):
#        bundle exec rails runner "a=Captain::Assistant.find(<ID>); c=a.config||{}; \
#          c['gazetteer']=JSON.parse(File.read('/tmp/config-gazetteer-conta6.json')); a.update!(config:c)"
# ============================================================================
