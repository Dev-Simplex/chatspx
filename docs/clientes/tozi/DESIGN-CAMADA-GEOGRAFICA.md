# Camada geográfica da Tozi — mapa + geo-inteligência da IA (design note)

> Handoff para retomar/continuar em outra sessão. Cobre: mapas (humano), correção dos bairros,
> mapa de imóveis em tempo real, e como a IA "enxerga" geografia (proximidade correta).
> Cliente: **Tozi** · conta HML **3** (`.232`) / PROD **6** (`3.82.215.109`). Isolamento: dado por conta,
> nunca no `assistant.liquid` compartilhado.

## 0. Princípio-guia (a "pegadinha")
A IA **não olha mapa**. LLM é ruim de raciocínio espacial com coordenada crua. Então:
- **Mapa = ferramenta para HUMANO** (equipe/ops/QA visual).
- **Geografia da IA = ferramentas com cálculo pré-feito** (Haversine, geocoding), consultadas via tool.
- Mapa e IA devem beber do **mesmo índice geográfico** do acervo. O humano vê; a IA consulta.

## 1. Os mapas (já existem, gerados local, grátis)
- **`mapa-sinop.html`** — bairro-level: centroides dos bairros, cor por região, tamanho por nº de imóveis.
  Gerado por `Temp/gen_map.py` a partir de `config-gazetteer-conta6.json`.
- **`mapa-imoveis-sinop.html`** — imóvel-level, **ao vivo do Vista**: 1.090 imóveis (1.041 com coord, 49 sem).
  Gerado por `Temp/gen_mapa_imoveis.py` (puxa o acervo direto da API pública do Vista; chave lida do vault
  `credenciais/tozi.md` em runtime — **nunca** embutida no HTML).
- Observado no imóvel-level: coords **boas em agregado** (clusterizam certo na malha). Aeroporto a O/SO do
  centro (confirma "vetor nobre = Oeste").

## 2. Correção dos bairros (estão tortos — e é arrumável)
Causa: o centroide do bairro é a **média** das coords dos seus imóveis; **1 imóvel com coord errada** no
Vista arrasta o ponto. Fixes (combinar):
1. **Localização do bairro = geocoding do nome OFICIAL** (ViaCEP → Nominatim/Google), não a média de imóveis.
2. **Rejeição de outlier** ao computar centroide (mediana; descartar coord a > X km do geocode oficial).
3. Bairros com 1–2 imóveis herdam a coord do imóvel — usar o geocode oficial nesses.

## 3. Mapa de imóveis em tempo real (a ideia do Paulo)
**Não precisa de "base grande".** 1.090 imóveis ≈ 300–500 KB; Leaflet planta fácil (com clustering, 10k+).
O ponto é **frescor/sync**, não tamanho. Duas arquiteturas, nenhuma com warehouse:

- **(a) Proxy ao vivo** — endpoint no backend consulta o Vista na hora → GeoJSON → mapa. Zero armazenamento,
  sempre atual. Custo: ~22 chamadas Vista por load (paginação de 50). Mitiga com cache curto (5–15 min).
- **(b) Cache periódico leve — RECOMENDADO** — job atualiza o acervo a cada ~15 min num cache
  (Redis/memória, ~1 MB). O mapa lê dele **E** a proximidade da IA fica **exata** (calcula sobre o acervo
  inteiro). Imóvel novo aparece no próximo refresh. É cache, não banco — some quando quiser, se reconstrói.

**"Todo imóvel que entra já aparece":** ✅ instantâneo no (a), ~15 min no (b).
Recomendo (b): resolve **mapa + proximidade da IA** de uma vez, footprint mínimo.

## 4. A busca por proximidade hoje — e o furo
`buscar_imovel_tool.rb` aceita `lat/lng` (+ `raio_km`), calcula Haversine **local** (o Vista compara coord
como string → range dele quebra com negativo) e ordena por distância. **Matematicamente correto.**
**Furo:** só considera os **50 imóveis mais recentes** (`Codigo desc`, `quantidade: 50`) que batem no filtro
— *depois* mede distância. Logo "mais próximo de X" **pode perder** imóveis realmente mais perto fora do
top-50. Morde mais em busca ampla. → O índice geo (item 3b) elimina isso: proximidade sobre o acervo todo.

## 5. Extensões de tool (o que falta pra "geo-IA" ficar redonda)
- **`buscar_imovel` proximidade exata:** trocar a amostra de 50 pelo índice geo completo (item 3b).
- **`perto_do_codigo`** (novo param no `buscar_imovel`): cliente vê o imóvel X e quer "outra opção perto" →
  pega a coord de X (mesmo padrão do `enviar_localizacao_imovel`, que já busca coord por código) → proximidade
  **excluindo X** → próximo mais perto de verdade. Hoje a IA não recebe a coord de cada imóvel no resultado,
  por isso não consegue re-ancorar — este param resolve.
- **`consultar_bairro`** (contrato em `consultar-bairro-contrato.md`): conhecimento do bairro (perfil/região/
  o-que-fica-perto), mapeando **CEP↔bairro-oficial↔nome-comercial-do-Vista** (resolve "cliente diz Aquarela,
  base tem Santa Cecília").

## 6. Fontes de dado (autoritativas, grátis/centavos — nada de LLM adivinhando)
| Camada | Fonte | Nota |
|---|---|---|
| Lista **oficial** de bairros + CEP | **Correios/ViaCEP** | `scripts/spx/tozi/viacep_bairros.py` (varredura de CEP) |
| Coords + contagem **comercial** | **Vista** (`/imoveis/listar`) | acervo ao vivo; chave no vault |
| **Pontos de referência** (hospital, faculdade, shopping) | **Google Places** | chave já existe (`buscar_lugar`) |
| Coords de bairro sem imóvel | **Google/Nominatim geocoding** | do nome oficial/CEP |
| Bairros/POIs suplementar | **OpenStreetMap/Overpass** | ⚠️ **ralo pra Sinop** (só suplemento) |
| Perfil/vocação (qualitativo) | LLM, camada **fina** e opcional | com guarda de custo |

## 7. Próximos passos
1. (LAN) Consolidar gazetteer canônico: ViaCEP (nomes oficiais) + Vista (comercial/coords) + geocoding.
2. Regenerar bairro-map com geocode oficial + outlier rejection (item 2).
3. Backend: endpoint `/tozi/mapa_imoveis` (proxy) + índice geo em cache (item 3b) → alimenta mapa e IA.
4. Estender tools (item 5). Aplicar por conta (3 → 6), com OK, dentro da cerimônia de isolamento.

## Artefatos relacionados
`gazetteer-sinop.json` · `mapa-mental-sinop.md` · `geocoding-reconciliacao.md` · `consultar-bairro-contrato.md`
· `scripts/spx/tozi/build_gazetteer_config.rb` · `scripts/spx/tozi/viacep_bairros.py` · `Temp/gen_map*.py`
