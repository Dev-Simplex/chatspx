# Relatório de estado + correções pendentes — IA Clara (Tozi, conta 6)

> **Data:** 2026-07-07 · **Alvo:** Tozi PRODUÇÃO (conta 6) · VM `3.82.215.109` · app em `/home/chatwoot/chatwoot`
> **Origem:** análise da conversa real [#18876](https://tozi.chatspx.app/app/accounts/6/conversations/18876) + sondagens read-only na API do Vista (produção).
> **Para o dev:** este documento traz 3 correções na IA de atendimento, com a mecânica do Vista já descoberta e o código pronto pra aplicar. Leia a seção 0 primeiro — ela explica por que o **git está desatualizado** em relação ao que roda no servidor.

---

## 0. ⚠️ Antes de tudo: o código do servidor está À FRENTE do git

O ChatSPX roda em VMs. Em teoria a branch `producao` seria a fonte de verdade e desceria pras VMs. **Na prática, as ferramentas da IA da Tozi foram editadas direto no servidor e nunca voltaram pro git.** Então, **hoje, o arquivo que roda na conta 6 é mais novo que o do repositório**.

Isso vale para os dois arquivos que este relatório mexe:

| Arquivo | No git (`enterprise/lib/captain/tools/`) | No servidor (conta 6, rodando) |
|---|---|---|
| `buscar_imovel_tool.rb` | **antigo** — sem o parâmetro `codigo`, sem `ValorCondominio`/`ValorIptu`, credencial via `ENV` direto | **novo** — tem `codigo`, `ValorCondominio`, `ValorIptu`, credencial por conta (concern `IntegrationCredentials`) |
| `enviar_fotos_imovel_tool.rb` | **antigo** — o `desc` do parâmetro tem `(ex: 6573)`, que fazia a IA mandar sempre o imóvel 6573 | **novo** — `desc` corrigido ("exatamente como veio no resultado da busca"), credencial por conta |

**Consequência prática (importante):** se alguém rodar um deploy da branch `producao` por cima do servidor, **regride essas duas ferramentas** (volta o bug do 6573, perde o `codigo`). 

**O que fazer (recomendação):**
1. **Reconciliar primeiro:** pegar a versão que está rodando no servidor (`cat` dos dois arquivos no box) → commitar no git como base → aplicar as correções deste relatório por cima → então o git volta a ser a fonte de verdade.
2. As correções abaixo já estão escritas **em cima da versão do servidor** (a real), não da versão velha do git.

> Como pegar a versão real do servidor:
> ```
> cat /home/chatwoot/chatwoot/enterprise/lib/captain/tools/buscar_imovel_tool.rb
> cat /home/chatwoot/chatwoot/enterprise/lib/captain/tools/enviar_fotos_imovel_tool.rb
> ```

**Depois de aplicar (qualquer uma das 3 correções que mexe em `.rb`):** é mudança de classe Ruby → **precisa reiniciar o worker** pra recarregar. Antes de reiniciar, rodar `RAILS_ENV=production bundle exec rails db:migrate:status` (regra da casa: migration pendente + restart = 500 em cadeia). As correções 1 e 3 são no **mesmo arquivo** (`buscar_imovel_tool.rb`) — aplicar juntas, um restart só.

---

## 1. Bug — a busca não lê a descrição do anúncio (ex.: "condomínio incluso")

### O que aconteceu (conversa 18876, imóvel 9769)
O cliente perguntou sobre o condomínio. A IA respondeu que **não estava incluso**. Mas a descrição real do imóvel no Vista diz **"Obs- Condominio incluso"** (o aluguel de R$ 2.950 já embute o condomínio).

### Por que
A ferramenta `buscar_imovel` só lê **campos estruturados**. O único sinal de condomínio é `ValorCondominio`, e a IA só menciona condomínio quando esse valor é **> 0**. Como o condomínio do 9769 está **embutido no aluguel**, o `ValorCondominio` vem **`"0"`** — e a informação verdadeira ("condomínio incluso") mora **só no texto livre da descrição**, que a ferramenta **nunca lia**.

Confirmado em produção:
```
ValorCondominio = "0"
DescricaoWeb    = "...Valor: R$2.950,00 ... Obs- Condominio incluso ..."  (666 caracteres)
```

### Mecânica do Vista (já descoberta — não precisa reinvestigar)
- O campo da descrição livre se chama **`DescricaoWeb`**.
- Ele **vem no `/imoveis/listar`** (o mesmo endpoint que a busca por código já usa) — confirmado.
- ⚠️ A descrição contém **telefones** ("Contato: (66) 3531-7222 / (66) 99633-6623") e um **parágrafo de disclaimer jurídico**. A IA **não pode** repassar telefone direto ao cliente (fura o funil de atendimento). Por isso a descrição tem que ser **higienizada** antes de entregar pro modelo.

### Correção (no `buscar_imovel_tool.rb`)
1. Adicionar `DescricaoWeb` ao `VISTA_FIELDS`.
2. No caminho **por código** (imóvel único), passar `detalhado: true`.
3. Quando `detalhado`, anexar a descrição **higienizada** (sem telefone/disclaimer).

Motivo de só mostrar a descrição no **código-lookup** (imóvel único) e não na lista de 5: custo de token e evitar 5 blocos de contato. Quando o cliente foca num imóvel específico ("e o 9769?"), a IA rebusca por código e aí recebe a descrição completa — cobre exatamente o caso da 18876 e todo "tem tal coisa nesse imóvel?".

*(Código completo na seção 3 — é o mesmo arquivo da correção de características.)*

---

## 2. Bug — envio de fotos: "todas juntas" e imóvel repetido

### O que aconteceu (conversa 18876)
Reconstrução do que a IA de fato enviou (forense das mensagens em produção): **31 imagens** de **4 imóveis diferentes**, com destaque para:

| Momento | O que saiu |
|---|---|
| **18:47:37 → 18:47:53 (16 s)** | **9 fotos de 3 imóveis diferentes de uma vez** (3+3+3) |
| 18:54 · 18:56 · 18:58 · 19:02 · 19:09 · 19:12 | mais rajadas de 3, dos mesmos imóveis |

Contagem por imóvel (identificados pelo prefixo do arquivo):

| Imóvel (prefixo) | Fotos | Nº de rajadas separadas |
|---|---|---|
| `iAKF3dHM…` | 6 | 2 (18:47 e 19:02) |
| `ic8A9i9Q9l…` | 9 | **3** (18:47, 18:54, 19:12) |
| `iCq7B8X548HusT9…` | 10 | **4** (18:47, 18:56, 18:58, 19:12) |
| `iDG9NV1p92iJgf7…` | 6 | 2 (19:09, 19:12) |

- **"Todas juntas":** às 18:47 saíram **9 fotos em 16 segundos** — a IA chamou `enviar_fotos_imovel` 3× seguidas (uma por imóvel que estava mostrando), e cada chamada despeja 3 fotos com só 2 s de intervalo. Da ótica do cliente, é um dilúvio.
- **"Repetida":** o **mesmo imóvel volta em várias rajadas** ao longo da conversa (o `ic8A9i9Q9l` apareceu 3 vezes; o `iCq7…`, 4 vezes). Não são arquivos byte-a-byte idênticos — é o **mesmo imóvel reenviado em blocos**, o que o cliente percebe como "de novo as fotos daquele apê".

### Por que (no código atual — `enviar_fotos_imovel_tool.rb`)
1. **Sem freio entre chamadas.** Nada impede a IA de chamar a ferramenta 3× no mesmo turno (um imóvel atrás do outro) → rajada de 9. O `sleep(2)` só espaça *dentro* de um lote de 3; não segura o próximo lote.
2. **Sem teto por imóvel.** A cada chamada com o mesmo código, o offset avança e manda +3 — sem limite. Daí o imóvel `iCq7…` acumular 10 fotos.
3. **Reset-on-empty é bomba latente de duplicata exata.** Quando o offset chega ao fim das fotos, o código **volta pra 0 e reenvia do começo** (linhas do `if batch.empty?`). Nesta conversa não disparou, mas basta a IA insistir num imóvel com poucas fotos pra gerar **fotos idênticas repetidas**.

### Correção proposta (2 partes)

**a) Código (`enviar_fotos_imovel_tool.rb`) — freio + teto + tirar o reenvio automático:**

- **Cooldown por conversa:** só permite um novo lote de fotos se o último lote foi há mais de ~90 s. Isso mata a rajada de 9 (a 2ª/3ª chamada no mesmo turno é barrada com um retorno tipo *"acabei de enviar fotos; espere o cliente reagir antes de mandar mais"*).
- **Teto por imóvel:** no máximo 6 fotos por código (2 lotes). Depois disso, retorna *"já enviei as principais desse imóvel"*.
- **Remover o reset-on-empty:** quando acabaram as fotos, **não** reenviar do zero — retornar *"já enviei todas as fotos desse imóvel"*. Elimina a duplicata exata latente.

```ruby
# --- trechos a mudar em enviar_fotos_imovel_tool.rb ---

BATCH = 3
SEND_INTERVAL = 2
COOLDOWN = 90   # s entre lotes de foto na MESMA conversa (freia a rajada multi-imóvel)
MAX_POR_IMOVEL = 6

def perform(tool_context, codigo:)
  conversation = find_conversation(tool_context&.state)
  return 'Não consegui identificar a conversa pra enviar as fotos.' unless conversation

  # FREIO: não deixa a IA despejar fotos de vários imóveis no mesmo turno.
  ultimo = conversation.custom_attributes['fotos_ultimo_envio_at'].to_i
  if ultimo.positive? && (Time.current.to_i - ultimo) < COOLDOWN
    return 'Você acabou de enviar fotos há pouco. NÃO envie mais agora — ' \
           'espere o cliente reagir. Só reenvie se ele pedir explicitamente.'
  end

  fotos = fetch_fotos(codigo)
  return 'Não encontrei fotos desse imóvel.' if fotos.blank?

  key = "fotos_offset_#{codigo}"
  sent = conversation.custom_attributes[key].to_i
  if sent >= [fotos.size, MAX_POR_IMOVEL].min
    # TETO / acabou: não reenvia do zero (evita duplicata) — avança a conversa.
    return "Já enviei as fotos principais do imóvel #{codigo}. NÃO reenvie — avance a conversa (interesse, visita)."
  end

  batch = fotos[sent, BATCH] || []
  return 'Não encontrei fotos desse imóvel.' if batch.empty?

  batch.each_with_index do |url, i|
    send_photo(conversation, url)
    sleep(SEND_INTERVAL) if i < batch.size - 1
  end

  conversation.update!(custom_attributes: conversation.custom_attributes.merge(
    key => sent + batch.size,
    'fotos_ultimo_envio_at' => Time.current.to_i
  ))

  restantes = [fotos.size, MAX_POR_IMOVEL].min - (sent + batch.size)
  if restantes.positive?
    "Enviei #{batch.size} fotos do imóvel #{codigo}. NÃO ofereça mais por conta própria — " \
      'avance a conversa. Se o cliente pedir mais, chame de novo.'
  else
    "Enviei as fotos principais do imóvel #{codigo}. Avance a conversa."
  end
end
```
*(O resto do arquivo — `fetch_fotos`, `send_photo` — fica igual.)*

**b) Comportamento da IA (config no banco da conta 6 — NÃO é código):**
Reforçar na instrução do agente: **enviar fotos de um imóvel por vez**; não mandar fotos de vários imóveis no mesmo turno; e não reenviar fotos por conta própria. (Isso é ajuste de prompt/persona no banco da conta 6, feito via o helper da Tozi — não vai no código compartilhado.)

> Números (`COOLDOWN = 90`, `MAX_POR_IMOVEL = 6`) são pontos de partida — ajustar conforme o Paulo achar bom o volume.

---

## 3. Melhoria — características na busca (piscina, móveis planejados, mobiliado…)

### O pedido
O Vista tem MUITA informação útil por imóvel (piscina, móveis planejados, mobiliado, churrasqueira, ar-condicionado…). Cliente pede "casa com piscina", "apê mobiliado". Hoje a `buscar_imovel` ignora tudo isso — nem mostra, nem filtra.

### Mecânica do Vista (descoberta e confirmada em produção — a parte que economiza dias)
O Vista tem **743 campos** no total; **149** são de característica. E há uma **assimetria** importante entre ler e filtrar:

**Para LER (mostrar ao cliente):** peça o campo **`Caracteristicas`** (nome simples, na lista de `fields`). O Vista devolve um **objeto só com as marcadas**, chaveado por rótulo com espaço/acento:
```
fields: ['Codigo', 'Caracteristicas']
→ 9769: {"Alarme"=>"Sim", "Ar Condicionado"=>"Sim", "Area Servico"=>"Sim", "Cerca Eletrica"=>"Sim", "Sacada"=>"Sim"}
→ 9698: {"Alarme"=>"Sim", "Area Servico"=>"Sim", "Cerca Eletrica"=>"Sim", "Lavabo"=>"Sim", "Piscina"=>"Sim", "Piso Porcelanato"=>"Sim"}
```
- Vem no `/listar` também (confirmado) → dá pra incluir na busca normal sem chamada extra.
- ⚠️ **Limitação do Vista:** esse objeto expõe só um **subconjunto** dos checkboxes que aparecem no painel web do Vista (no 9769, veio 5 das ~14 do print). É o que a API entrega — não dá pra "consertar" pelo nosso lado. Ainda assim é bem útil.

**Para FILTRAR (buscar):** use o **nome CamelCase** do campo como chave de filtro, valor `'Sim'` (NÃO funciona ler esses campos no topo — só filtrar):
```
filter: {'Cidade'=>'Sinop', 'Status'=>['like','%alug%'], 'Piscina'=>'Sim'}
→ HTTP 200, total = 5  (5 imóveis pra alugar com piscina)
```
Nomes CamelCase saem do endpoint `/imoveis/listarcampos`. Os mais úteis (match 1:1):
`Piscina, Mobiliado, SemiMobiliado, Churrasqueira, ArCondicionado, Sacada, Closet, Escritorio, Lavabo, Quintal, Edicula, Varanda, Lareira, Sauna, AguaQuente, AquecimentoSolar, Elevador, Academia, Playground, SalaoFestas, Portaria24Hrs`.

> "Móveis planejados" é **fuzzy** no Vista — são vários campos (`CozinhaInternaMoveisPlanejados`, `QuartoMoveisPlanejados`, `ClosetMoveisPlanejados`, `AreaServicoMoveisPlanejados`…). Não dá match limpo 1:1 pra filtro. Recomendação: **não** filtrar por "móveis planejados" (mostrar via `Caracteristicas`/descrição, sim). Filtrar só pelos de match limpo.

### Correção (no `buscar_imovel_tool.rb`)
1. Adicionar `Caracteristicas` ao `VISTA_FIELDS` → **mostrar** as características de cada imóvel no resultado.
2. Novo parâmetro `caracteristicas` (o que o cliente exigir) → **filtrar** via dicionário termo→campo.

### Arquivo completo proposto (`buscar_imovel_tool.rb` — já com as correções 1 e 3)

```ruby
class Captain::Tools::BuscarImovelTool < Captain::Tools::BasePublicTool
  description 'Busca imóveis no acervo da Tozi (sistema Vista) e retorna até 5 opções com o link correto do site. ' \
              "Use status_tipo='venda' para comprar e status_tipo='locacao' para alugar. " \
              'Para proximidade geográfica, passe lat/lng (do buscar_localizacao OU da localização que o cliente enviou): ' \
              'retorna os mais próximos, ordenados pela distância em km.'

  param :status_tipo, type: 'string', desc: "'venda' para comprar, 'locacao' para alugar", required: true
  param :codigo, type: 'string',
                 desc: 'Código do imóvel que o cliente informar (do anúncio, da placa do imóvel, ou do site). Quando presente, busca o imóvel EXATO por esse código — ignore os outros filtros.', required: false
  param :categoria, type: 'string', desc: 'Casa, Apartamento, Terreno, Sala Comercial, Kitnet. Vazio se não especificou.', required: false
  param :bairro, type: 'string', desc: 'Bairro/condomínio em Sinop. Vazio se não especificou.', required: false
  param :endereco, type: 'string',
                   desc: 'Rua, avenida ou logradouro, quando o cliente especificar. Estreita a busca dentro do bairro.', required: false
  param :valor_max, type: 'number', desc: 'Valor máximo: aluguel mensal pra locação, valor total pra venda.', required: false
  param :dormitorios, type: 'number', desc: 'Quantidade de dormitórios.', required: false
  param :caracteristicas, type: 'string',
                          desc: 'Características que o cliente exigir explicitamente, separadas por vírgula. Só o que o cliente pediu; vazio se ele não exigiu nada.', required: false
  param :lat, type: 'string', desc: 'Latitude do ponto de referência.', required: false
  param :lng, type: 'string', desc: 'Longitude do ponto de referência.', required: false
  param :raio_km, type: 'number', desc: 'Só quando o cliente limitar a distância (ex: "até 2 km").', required: false

  VISTA_FIELDS = %w[Codigo ImoCodigo Categoria Status Dormitorios Cidade Bairro BairroComercial ValorLocacao ValorVenda TituloSite
                    ValorCondominio ValorIptu DescricaoWeb Caracteristicas Latitude Longitude].freeze
  META_KEYS = %w[total paginas pagina quantidade].freeze

  # Termo do cliente -> campo CamelCase do Vista (filtro {campo => 'Sim'}). Só match 1:1.
  # "Móveis planejados" é fuzzy (vários campos) e fica de fora do filtro de propósito.
  CARACTERISTICAS_FILTRO = {
    'piscina' => 'Piscina', 'mobiliado' => 'Mobiliado', 'semi mobiliado' => 'SemiMobiliado',
    'churrasqueira' => 'Churrasqueira', 'ar condicionado' => 'ArCondicionado', 'sacada' => 'Sacada',
    'closet' => 'Closet', 'escritorio' => 'Escritorio', 'lavabo' => 'Lavabo', 'quintal' => 'Quintal',
    'edicula' => 'Edicula', 'varanda' => 'Varanda', 'lareira' => 'Lareira', 'sauna' => 'Sauna',
    'agua quente' => 'AguaQuente', 'aquecimento solar' => 'AquecimentoSolar', 'elevador' => 'Elevador',
    'academia' => 'Academia', 'playground' => 'Playground', 'salao de festas' => 'SalaoFestas',
    'portaria 24h' => 'Portaria24Hrs'
  }.freeze

  def perform(_tool_context, status_tipo:, categoria: nil, bairro: nil, endereco: nil, valor_max: nil,
              dormitorios: nil, caracteristicas: nil, lat: nil, lng: nil, raio_km: nil, codigo: nil)
    # Busca direta por CÓDIGO (placa/anúncio/site) — independe de venda/locação, traz descrição.
    if codigo.present?
      cod = codigo.to_s.gsub(/\D/, '')
      achados = fetch_vista({ 'Codigo' => cod }, quantidade: 1)
      return "Não achei nenhum imóvel com o código #{cod} no nosso sistema." if achados.blank?

      return format_listings(achados, achados.first['Status'].to_s.match?(/vend/i), detalhado: true)
    end
    venda = status_tipo.to_s == 'venda'
    filter = { 'Cidade' => 'Sinop' }
    filter['Status'] = venda ? ['like', '%vend%'] : ['like', '%alug%']
    filter[venda ? 'ValorVenda' : 'ValorLocacao'] = ['', valor_max] if valor_max.present?
    filter['Categoria'] = categoria if categoria.present?
    filter['Bairro'] = ['like', "%#{bairro}%"] if bairro.present?
    filter['Endereco'] = ['like', "%#{endereco}%"] if endereco.present?
    filter['Dormitorios'] = dormitorios if dormitorios.present?
    aplicar_caracteristicas(filter, caracteristicas)

    geo = lat.present? && lng.present?
    imoveis = fetch_vista(filter, quantidade: geo ? 50 : 5)
    return 'Nenhum imóvel encontrado com esses critérios.' if imoveis.blank?
    return format_listings(imoveis, venda) unless geo

    format_by_distance(imoveis, venda, lat.to_f, lng.to_f, raio_km.presence&.to_f)
  rescue StandardError => e
    Rails.logger.warn("[BuscarImoveisTool] #{e.message}")
    'Não consegui buscar os imóveis agora.'
  end

  private

  def aplicar_caracteristicas(filter, caracteristicas)
    return if caracteristicas.blank?

    caracteristicas.to_s.downcase.split(/[,;]/).each do |termo|
      t = termo.strip.unicode_normalize(:nfd).gsub(/\p{Mn}/, '')
      campo = CARACTERISTICAS_FILTRO[t]
      filter[campo] = 'Sim' if campo
    end
  end

  def fetch_vista(filter, quantidade: 5)
    base = vista_base_url
    pesquisa = {
      fields: VISTA_FIELDS,
      filter: filter,
      order: { 'Codigo' => 'desc' },
      paginacao: { pagina: 1, quantidade: quantidade }
    }
    resp = HTTParty.get(
      "#{base}/imoveis/listar",
      query: { key: vista_api_key, showtotal: 1, pesquisa: pesquisa.to_json },
      headers: { 'Accept' => 'application/json' },
      timeout: 15
    )
    return [] unless resp.code == 200

    data = resp.parsed_response
    data = JSON.parse(data) if data.is_a?(String)
    return [] unless data.is_a?(Hash)

    data.reject { |k, _| META_KEYS.include?(k) }.values.select { |v| v.is_a?(Hash) }
  end

  def format_by_distance(imoveis, venda, lat, lng, raio)
    com_geo = with_distances(imoveis, lat, lng)
    return 'Os imóveis encontrados não têm localização cadastrada — refaça a busca por bairro.' if com_geo.empty?

    com_geo.sort_by! { |im| im['dist_km'] }
    return format_listings(com_geo, venda, header: 'Mais próximos da referência:') if raio.blank?

    no_raio = com_geo.select { |im| im['dist_km'] <= raio }
    return format_listings(no_raio, venda) if no_raio.any?

    format_listings(com_geo.first(3), venda,
                    header: "Nenhum imóvel a até #{raio.round} km da referência. Os mais próximos são:")
  end

  def with_distances(imoveis, lat, lng)
    imoveis.filter_map do |im|
      ilat = im['Latitude'].to_f
      ilng = im['Longitude'].to_f
      next if ilat.zero? && ilng.zero?

      im.merge('dist_km' => haversine_km(lat, lng, ilat, ilng))
    end
  end

  def haversine_km(lat1, lng1, lat2, lng2)
    rad = Math::PI / 180
    dlat = (lat2 - lat1) * rad
    dlng = (lng2 - lng1) * rad
    a = (Math.sin(dlat / 2)**2) + (Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * (Math.sin(dlng / 2)**2))
    2 * 6371 * Math.asin(Math.sqrt(a))
  end

  def format_listings(imoveis, venda, header: nil, detalhado: false)
    linhas = imoveis.first(5).map do |im|
      valor = venda ? "R$ #{im['ValorVenda']}" : "R$ #{im['ValorLocacao']}/mês"
      dorm = im['Dormitorios'].to_i.positive? ? "#{im['Dormitorios']} quartos, " : ''
      dist = im['dist_km'] ? " — a #{format('%.1f', im['dist_km'])} km da referência" : ''
      linha = "(cód #{im['Codigo']}) #{im['Categoria']} #{dorm}no #{im['Bairro']}, " \
              "#{valor}#{format_taxas(im)}#{format_extras(im)}#{dist}. #{build_url(im, venda)}"
      desc = descricao_limpa(im['DescricaoWeb'])
      linha += "\n#{desc}" if detalhado && desc.present?
      linha
    end
    "#{header || "Encontrei #{linhas.size} opção(ões):"}\n#{linhas.join("\n")}"
  end

  # Condomínio/IPTU só quando o Vista traz o valor (>0); nunca inventa.
  def format_taxas(im)
    parts = []
    parts << "condomínio R$ #{im['ValorCondominio']}" if im['ValorCondominio'].to_f.positive?
    parts << "IPTU R$ #{im['ValorIptu']}" if im['ValorIptu'].to_f.positive?
    parts.any? ? " (#{parts.join(', ')})" : ''
  end

  # Características marcadas (objeto Caracteristicas do Vista), curto, pra IA citar.
  def format_extras(im)
    car = im['Caracteristicas']
    return '' unless car.is_a?(Hash)

    marcadas = car.select { |_, v| v.to_s == 'Sim' }.keys
    marcadas.any? ? " [#{marcadas.first(8).join(', ').downcase}]" : ''
  end

  # Descrição do anúncio (DescricaoWeb) SEM telefone nem disclaimer — a IA não pode
  # vazar contato direto (fura o handoff). Só o corpo útil (o que está incluso, etc.).
  def descricao_limpa(texto)
    linhas = texto.to_s.split(/\r?\n/).reject do |l|
      l.match?(/contato|telefone|whats/i) ||
        l.match?(/\(?\d{2}\)?[\s.-]*\d{4,5}[\s.-]?\d{4}/) ||
        l.match?(/os valores.*sem pr[eé]vio aviso|mercado imobili/i)
    end
    txt = linhas.join("\n").gsub(/\(?\d{2}\)?[\s.-]*\d{4,5}[\s.-]?\d{4}/, '').gsub(/\n{3,}/, "\n\n").strip
    txt.length > 600 ? "#{txt[0, 600].rstrip}…" : txt
  end

  # O site da Tozi acha o imóvel pelo ImoCodigo (não pelo Codigo do Vista); o slug é cosmético.
  def build_url(im, venda)
    bairro = im['BairroComercial'].presence || im['Bairro']
    parts = [venda ? 'venda' : 'aluguel', slugify(im['Categoria'])]
    parts << "#{im['Dormitorios']}-dormitorios" if im['Dormitorios'].to_i.positive?
    parts << slugify(bairro) << slugify(im['Cidade'])
    id = im['ImoCodigo'].presence || im['Codigo']
    "https://www.#{site_domain}/#{parts.reject(&:blank?).join('-')},#{id}"
  end

  def slugify(str)
    str.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '')
       .downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')
  end
end
```

> **Nota:** este arquivo usa `vista_base_url` / `vista_api_key` / `site_domain`, que vêm do concern `IntegrationCredentials` (credencial por conta) — o mesmo que a versão do servidor já usa. Confirmar que o concern está presente no repo ao reconciliar (hoje ele também está off-git).

---

## 4. Resumo: onde cada coisa cai + passos de deploy

| # | Correção | Tipo | Onde | Precisa restart? |
|---|---|---|---|---|
| 1 | Ler descrição (`DescricaoWeb`) | **código** | `buscar_imovel_tool.rb` | Sim (worker) |
| 3 | Características (mostrar + filtrar) | **código** | `buscar_imovel_tool.rb` (mesmo arquivo do #1) | Sim (worker) |
| 2a | Freio/teto de fotos | **código** | `enviar_fotos_imovel_tool.rb` | Sim (worker) |
| 2b | "1 imóvel por vez, não reenviar" | **config (banco conta 6)** | prompt do agente, via helper da Tozi | Não |

**Sequência sugerida:**
1. Reconciliar as versões do servidor pro git (seção 0).
2. Aplicar #1 + #3 no `buscar_imovel_tool.rb` e #2a no `enviar_fotos_imovel_tool.rb`.
3. `RAILS_ENV=production bundle exec rails db:migrate:status` → se limpo, reiniciar o worker (`chatwoot-worker`).
4. Testar (seção 5).
5. #2b (config) — ajuste de prompt no banco da conta 6, sem deploy.

**Só a conta 6 usa essas ferramentas** (dependem das credenciais Vista, que só a Tozi tem) — então o impacto é isolado à Tozi, mesmo o arquivo estando na árvore compartilhada.

---

## 5. Como testar depois de aplicar

- **Descrição/condomínio (#1):** na conversa, pedir o imóvel **9769** → a IA deve receber a descrição com "condomínio incluso" e responder certo (que já está incluso no aluguel). Não pode aparecer telefone.
- **Características (#3):**
  - Busca: "casa pra alugar com piscina" → deve filtrar (`Piscina=Sim`) e retornar imóveis com piscina.
  - Exibição: cada resultado deve mostrar as características entre colchetes (ex.: `[alarme, ar condicionado, sacada]`).
- **Fotos (#2):** pedir fotos de 2 imóveis em seguida → o 2º pedido no mesmo turno deve ser **barrado** pelo cooldown (a IA não despeja tudo junto). Pedir muitas fotos do mesmo imóvel → para no teto, sem repetir.

---

## Apêndice — como isto foi levantado (scripts read-only)

Tudo confirmado com sondagens **somente-leitura** na API do Vista de produção (endpoints `GET /imoveis/listar`, `/imoveis/detalhes`, `/imoveis/listarcampos`) e leitura da conversa 18876 no banco. Nenhuma escrita, nenhum restart. Fatos-chave confirmados:
- `DescricaoWeb` existe e vem no `/listar` (666 ch pro 9769; contém "Condominio incluso"); `ValorCondominio` do 9769 = `"0"`.
- `Caracteristicas` (campo simples) devolve objeto rótulo→"Sim" das marcadas; vem no `/listar`.
- Filtro `{'Piscina'=>'Sim'}` no `/listar` → 5 imóveis (locação, Sinop). Ler o campo no topo devolve `nil` — só filtra.
- Vista: 743 campos totais, 149 de característica (via `/imoveis/listarcampos`).
