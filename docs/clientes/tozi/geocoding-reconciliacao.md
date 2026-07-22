# Geocoding do gazetteer — reconciliacao Vista x pesquisa (v2, inversao)

- Imoveis no acervo (Sinop): **1091**
- Bairros distintos no acervo: **233**  (descartados como nao-bairro: 10)
- Bairros do acervo COM perfil: **165**  (exato: 147 · nucleo: 18)
- Bairros do acervo SEM perfil: **58**
- Bairros so no gazetteer (sem imovel hoje): **70**
- Conflitos de regiao (gazetteer x centroide): **105**  (na duvida, vale o centroide)
- Long-tail posicionado por centroide: **68**
- Total no config: **293** bairros · **100** pontos

## Bairros do acervo SEM perfil (tem imovel — candidatos a enrich dirigido)
- **Residencial Belvedere II** — regiao: Sul · 2 imoveis
- **Condominio Reserva Celeste** — regiao: Sul/Leste · 1 imoveis
- **Portal dos Sonhos** — regiao: Sul · 1 imoveis
- **RESIDENCIAL MAISON  MONET** — regiao: Oeste · 1 imoveis
- **EDIFICIO RESIDENCIAL MAISON MONET** — regiao: Oeste · 1 imoveis
- **Jardim Londrina** — regiao: Sul · 1 imoveis
- **Bairro Angélica** — regiao: Sul · 1 imoveis
- **OASIS DA AMAZONIA** — regiao: Norte · 1 imoveis
- **RESIDENCIAL PRIVILLEGE** — regiao: ? · 1 imoveis
- **Jardim das Oliveiras II** — regiao: Norte · 1 imoveis
- **Acqua Spl** — regiao: Oeste · 1 imoveis
- **Ares Eco** — regiao: Oeste · 1 imoveis
- **Gaia By** — regiao: Oeste · 1 imoveis
- **Guanabara** — regiao: Oeste · 1 imoveis
- **Parque Sinop** — regiao: Oeste · 1 imoveis
- **Genebra Residence** — regiao: Oeste · 1 imoveis
- **Residencial Rhodivi Morada do Bosque** — regiao: Sul/Leste · 1 imoveis
- **Empreendimento Zurique** — regiao: Oeste · 1 imoveis
- **Duottori Residence** — regiao: Sul · 1 imoveis
- **Elleva Jardins** — regiao: Leste · 1 imoveis
- **Elleva Studios** — regiao: Oeste · 1 imoveis
- **Blend** — regiao: Central · 1 imoveis
- **Loris Domus** — regiao: ? · 1 imoveis
- **Méditerranée** — regiao: Oeste · 1 imoveis
- **Reserve Belo Horizonte** — regiao: Sul/Oeste · 1 imoveis
- **Pacaembu** — regiao: Central · 1 imoveis
- **Cedros** — regiao: ? · 1 imoveis
- **Carvalho** — regiao: Leste · 1 imoveis
- **Residencial Infinity** — regiao: Oeste · 1 imoveis
- **Bairro Lidia** — regiao: ? · 1 imoveis
- **Atlântica** — regiao: ? · 1 imoveis
- **Residencial Belvedere I** — regiao: Sul/Leste · 1 imoveis
- **Jardim Bella Morada II** — regiao: Sul · 1 imoveis
- **Residencial Kaiabi** — regiao: Norte · 1 imoveis
- **Jardim Roma** — regiao: Sul · 1 imoveis
- **Jardim Conquista** — regiao: Central · 1 imoveis
- **Residencial Villa Itália** — regiao: Sul · 1 imoveis
- **Jardim Milão II** — regiao: Sul · 1 imoveis
- **Condomínio Rural Recanto das Águas** — regiao: ? · 1 imoveis
- **Residencial Villa Toscana II** — regiao: Sul/Leste · 1 imoveis
- **Condomínio de Chácaras Mato Grosso** — regiao: Sul · 1 imoveis
- **Condomínio Recanto dos Ipês** — regiao: ? · 1 imoveis
- **Comunidade Vitória** — regiao: Sul/Leste · 1 imoveis
- **Condomínio Náutico Portal do Lago** — regiao: ? · 1 imoveis
- **Talismã** — regiao: Leste · 1 imoveis
- **Residencial Panamby II** — regiao: Sul/Leste · 1 imoveis
- **Reserva Celeste** — regiao: Sul/Leste · 1 imoveis
- **Residencial Santa Rosa** — regiao: Sul · 1 imoveis
- **Mondrian** — regiao: Oeste · 1 imoveis
- **Jardim Milão** — regiao: Sul · 1 imoveis
- **Residencial Belvedere III** — regiao: Sul/Leste · 1 imoveis
- **Jardim Belvedere** — regiao: Sul · 1 imoveis
- **São Lucas** — regiao: Oeste · 1 imoveis
- **Primor das Aguias** — regiao: Norte · 1 imoveis
- **Privillege Residencial** — regiao: Norte · 1 imoveis
- **Jardim Acacias** — regiao: ? · 1 imoveis
- **Maria Carolina I** — regiao: Norte · 1 imoveis
- **Residencial Kayabi** — regiao: ? · 1 imoveis

## Conflitos de regiao (gazetteer disse X, centroide diz Y — centroide manda)
| Bairro | Gazetteer | Centroide | Imoveis |
|---|---|---|---|
| Residencial Aquarela Das Artes | leste | Oeste | 56 |
| Residencial Paris | leste | Oeste | 36 |
| Residencial Florença | a confirmar | Oeste | 33 |
| Platini Urban Park | a confirmar | Sul/Oeste | 24 |
| Parque Amazonas | arque Amazon | Sul/Oeste | 23 |
| Jardim Imperial | oeste | Central | 23 |
| Jardim Curitiba | oeste | Sul | 23 |
| Residencial Parque do Lago | a confirmar | Oeste | 23 |
| Residencial Recanto Suíço | a confirmar | Oeste | 20 |
| Jardim Belo Horizonte | central | Sul/Oeste | 20 |
| Aquarela dos Poemas | leste | Norte/Oeste | 20 |
| Condomínio Aquarela da Mata | leste | Oeste | 15 |
| Residencial Aquarela Brasil | norte | Oeste | 14 |
| Sonhalto Videira | a confirmar | Sul | 14 |
| Jardim Bougainville | a confirmar | Sul/Oeste | 13 |
| Jardim das Oliveiras | oeste | Norte | 13 |
| Residencial Riviera Suíça | norte | Oeste | 13 |
| Jardim Celeste | oeste | Sul | 12 |
| Jardim Terra Rica | a confirmar | Sul | 12 |
| Residencial Santa Cecília | Oeste | Norte/Oeste | 11 |
| Setor Residencial Norte | norte | Central | 11 |
| Residencial Ipanema | a confirmar | Oeste | 11 |
| Jardim Itália III | norte | Norte/Oeste | 10 |
| Jardim Maringá | leste | Central | 10 |
| Jardim Paraíso II | Sinop/MT — bairro Jardim Paraíso (região próxima ao centro, eixo da Av. dos Ingás) | Sul/Oeste | 10 |
| Jardim Botânico | oeste | Sul | 10 |
| Residencial Sonhalto Videira | a confirmar | Sul | 10 |
| Loteamento Alto da Glória | a confirmar | Sul | 10 |
| Portal da Mata | leste | Oeste | 8 |
| Jardim Copacabana | oeste | Sul | 8 |
| Jardim Portinari | a confirmar | Oeste | 8 |
| Residencial Santa Catarina | Sinop - MT | Sul | 7 |
| Residencial Nossa Senhora Aparecida | a confirmar | Oeste | 6 |
| Residencial Bella Suíça | a confirmar | Oeste | 6 |
| Parque das Araras | a confirmar | Norte | 6 |
| Setor Residencial Sul | sul | Central | 6 |
| Jardim das Acácias | a confirmar | Norte | 6 |
| Residencial Cidade Jardim | a confirmar | Leste | 6 |
| Jardim Paraíso | central | Sul/Oeste | 6 |
| Loteamento Florais da Amazônia | a confirmar | Norte/Leste | 6 |
| Jardim Morumbi | a confirmar | Sul | 5 |
| Residencial Buritis | a confirmar | Sul/Leste | 5 |
| jardim florença | central | Oeste | 5 |
| Jardim Iporã | oeste | Leste | 5 |
| Quatro Estações Boulevard | a confirmar | Sul | 5 |
| Condomínio Tuim Residencial | leste | Sul/Leste | 4 |
| Carpe Diem | leste | Oeste | 4 |
| Jardim Viena | a confirmar | Sul | 4 |
| Jardim Ibirapuera | oeste | Sul | 4 |
| Residencial Bonne Vie | a confirmar | Sul | 4 |
| Residencial San Martini | a confirmar | Oeste | 4 |
| Jardim Santa Mônica | a confirmar | Sul | 3 |
| Setor Industrial | central | Sul/Leste | 3 |
| Residencial São Francisco | a confirmar | Sul/Leste | 3 |
| Jardim Umuarama | a confirmar | Sul | 3 |
| Residencial São Lourenço | a confirmar | Leste | 3 |
| Jardim Jacarandás | central | Sul | 3 |
| Loteamento Menino Jesus II | a confirmar | Sul | 3 |
| Loteamento Bom Jardim | a confirmar | Sul/Leste | 3 |
| Condomínio de Chácaras Jamari | Sul | Sul/Leste | 3 |
| Jardim Veneza | a confirmar | Norte | 3 |
| Jardim Dubai | a confirmar | Leste | 3 |
| Residencial José Adriano Leitão | a confirmar | Sul | 3 |
| Residencial Sabrina II | a confirmar | Sul | 3 |
| Cidade Jardim | a confirmar | Leste | 3 |
| Eunice | a confirmar | Oeste | 2 |
| Setor Industrial Norte | norte | Leste | 2 |
| Jardim Novo Horizonte | central | Norte | 2 |
| Residencial Delta | a confirmar | Central | 2 |
| Residencial Jequitibás | a confirmar | Norte | 2 |
| Jardim Safira | a confirmar | Norte/Leste | 2 |
| Residencial Canadá | a confirmar | Norte/Leste | 2 |
| Jardim das Itaúbas | central | Sul | 2 |
| Residencial Panamby | a confirmar | Sul | 2 |
| Jardim Toledo | Jardim Toled | Norte/Leste | 2 |
| Jardim Boa Esperança | norte | Norte/Oeste | 2 |
| AQUARELA DAS ARTES | leste | Oeste | 2 |
| Residencial Nossa Senhora de Fátima | a confirmar | Sul/Oeste | 2 |
| Jardim São Paulo | a confirmar | Norte | 2 |
| Jardim Barcelona II | a confirmar | Oeste | 2 |
| Residencial Gente Feliz | a confirmar | Norte/Leste | 2 |
| Jardim Monte Carlo | a confirmar | Sul | 2 |
| Jardim dos Ipes | central | Norte/Oeste | 2 |
| Residencial Jardim Araguaia | a confirmar | Norte | 2 |
| Portal do Servidor | a confirmar | Leste | 1 |
| Jardim das Orquídeas | oeste | Norte | 1 |
| SAO FRANCISCO | a confirmar | Sul/Leste | 1 |
| Zona Rural | rural | Norte | 1 |
| Jardim São Lourenço | a confirmar | Norte | 1 |
| Residencial das Acácias | a confirmar | Norte | 1 |
| Residencial Bella Suíça III | norte | Sul/Oeste | 1 |
| Jardim Vitória Régia | a confirmar | Norte/Oeste | 1 |
| Residencial Platini Urban Park | a confirmar | Sul/Oeste | 1 |
| Montreal Park | a confirmar | Sul | 1 |
| Jardim Eunice | a confirmar | Oeste | 1 |
| Loteamento Campo Verde | a confirmar | Norte | 1 |
| Quinta da Pampulha | norte | Sul/Oeste | 1 |
| Residencial Campo Verde | a confirmar | Norte/Oeste | 1 |
| Jardim das Azaleias | oeste | Norte | 1 |
| Jardim Atenas | oeste | Sul | 1 |
| Jardim Pequena Londres | central | Sul | 1 |
| Residencial Perola | a confirmar | Sul | 1 |
| Jardim dos Tarumãs | central | Norte | 1 |
| Residencial Monte Carlo | a confirmar | Oeste | 1 |
| Residencial Sabrina III | a confirmar | Sul | 1 |

## Descartados como nao-bairro (free-text no campo Bairro do Vista)
Chácara de Lazer Boa Esperança (2) · Perimetral Sinop (1) · Chácara (1) · Estrada Nanci (1) · Chácaras Canarinho (1) · Chácara vitória (1) · av Jequitibas (1) · Chacaras (1) · Chácaras de Sinop (1) · DE CHACARAS (1)

## So no gazetteer (conhecimento, sem imovel hoje)
Alameda das Cores Residencial · Alto da Gloria · Associação Comunitária Rural Estrada Atlântica · Bairro Nossa Senhora de Fátima · Camping Club · Chácara Planalto · Chácara de Lazer Boa Esperança · Chácara de Lazer Boa Vista · Chácara de Lazer Comunidade Vitória · Chácara de Lazer Maria Carolina I · Chácara de Lazer Maria Carolina II · Chácara de Lazer Monaliza · Chácara de Lazer São Cristóvão · Chácara de Lazer São Cristóvão II · Cidade Alta · Comunidade Betel · Comunidade Boa Vista · Comunidade Nossa Senhora de Lourdes · Condomínio Residencial Camping Club · Distrito Industrial · Gleba Mercedes · Jardim América · Jardim Araguaia · Jardim Barcelona · Jardim Califórnia · Jardim Itália · Jardim Maria Carolina · Jardim Maria Vindilina I · Jardim Novo Estado · Jardim Oriente · Jardim Planalto · Jardim Santa Rita · Jardim Violetas · Jardim das Nacoes II · Jardim das Nacoes III · Jardim das Primaveras · Jardim do Ouro · LIC Norte · LIC Sul · Loteamento Menino Jesus · Loteamento Menino Jesus I · Loteamento Umuarama II · Loteamento Village · Moinho dos Ventos · Moinhos dos Ventos · Parque Florestal · Recanto Suico · Residencial Adalgiza · Residencial Boa Vista · Residencial Brasília · Residencial Ipiranga · Residencial Jaraguá · Residencial Lisboa · Residencial Maripá · Residencial Modrian · Residencial Nico Baracat · Residencial Nossa Senhora Aparecida II · Residencial Novo Jardim · Residencial Recanto dos Pássaros · Residencial Sabrina · Residencial Sabrina I · Residencial Sebastião de Matos · Residencial Sebastião de Matos II · Residencial Shalon · Rio Ferro · Santa Felicidade · São Cristóvão · Vida Nova · Vila Itália · Villa Verde Residencial
