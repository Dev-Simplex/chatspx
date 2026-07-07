# Contrato da tool `consultar_bairro` (Fase 2 — spec)

> Camada de **conhecimento residente** da cidade para a IA da Tozi. Complementa o *mapa mental*
> (sempre no contexto, em `config['instructions']`) servindo o **detalhe sob demanda** e o
> **long tail** (~90 loteamentos) que não cabe no prompt. Fonte de dados: `gazetteer-sinop.json`.
>
> Status: **desenho**. Não implementar/deployar antes do geocoding (Fase 2) e da cerimônia de
> isolamento (helper `tozi-prod`, conta 6). Este arquivo é a especificação, não código vivo.

## Onde encaixa (não confundir as tools)

| Cliente quer… | Tool | O que faz |
|---|---|---|
| Conhecer/recomendar bairro (perfil, região, o que fica perto, vizinhos) | **`consultar_bairro`** | lê o gazetteer da conta, retorna registro(s) |
| Achar um comércio/ponto nomeado → coordenadas p/ proximidade | `buscar_lugar` | Google Places (já existe, parado no `Temp/`) |
| Listar imóveis do acervo | `buscar_imovel` | Vista API |
| Mandar o pin no mapa | `enviar_localizacao` / `enviar_localizacao_imovel` | anexo `location` nativo |

`consultar_bairro` **não** lista imóvel e **não** geocodifica comércio. Ele é o "corretor que mora
na cidade": diz o perfil do bairro e orienta; a ponte pro acervo é devolver o **nome** do bairro
pra alimentar o `buscar_imovel`.

## Interface

**Nome:** `consultar_bairro`

**Descrição (para o modelo):**
> Consulta o conhecimento local de Sinop — perfil, região, avenidas, o que fica perto, vizinhos e
> âncoras de um bairro/loteamento — ou recomenda bairros por critério. Use para falar da cidade como
> quem mora nela e para orientar o cliente. Não lista imóveis (isso é o `buscar_imovel`) nem
> geocodifica comércio (isso é o `buscar_lugar`).

**Parâmetros** (todos opcionais; a IA passa pelo menos um — descrições falam da ORIGEM, nunca de exemplo):

| Param | Tipo | Descrição (origem do valor) |
|---|---|---|
| `bairro` | string | O bairro, loteamento ou condomínio como o cliente mencionou; casa por aproximação contra o acervo da conta. |
| `regiao` | string | A zona/lado da cidade, quando o cliente delimita por região em vez de nomear um bairro. |
| `perfil` | string | Em texto livre, a vocação ou padrão de bairro que o cliente descreve quando não nomeia um. |
| `perto_de` | string | O ponto de referência que o cliente usou como âncora, quando ele se orienta por um lugar conhecido. |

**Retorno** (texto para o modelo, no estilo das outras tools — string formatada, não JSON):

- **Casou 1+ bairros** (via `bairro`): até 3 blocos, cada um —
  `**{Nome}** — {região} · {perfil/faixa} · corta: {avenidas} · perto: {âncoras} · vizinhos: {…}`
  seguido de 1 linha-guia: *"Pra ver imóveis aí, use buscar_imovel com bairro={Nome}."*
- **Veio por critério** (`regiao` / `perfil` / `perto_de`): lista dos bairros que batem, 1 linha cada,
  ordenada por relevância — para a IA sugerir opções ao cliente.
- **Não achou:** *"Não tenho '{termo}' no meu mapa de Sinop."* + dica de pedir ao cliente uma
  referência/zona (sem inventar bairro).

Regra de conteúdo do retorno: **só dado real do gazetteer**. Faixa é qualitativa (padrão de corretor),
**nunca** vira preço — preço/estoque sempre do `buscar_imovel` (Vista).

## Backing / armazenamento (decisão de isolamento)

O gazetteer vive como **dado da conta**, carregado e filtrado por `account_id` — recomendação:
`assistant.config['gazetteer']` (JSONB já existente no molde behavior/config), com os registros
compactos por bairro (nome, região, perfil, faixa, avenidas, perto, vizinhos). Assim:

- Tozi tem o de Sinop; outro cliente teria a cidade dele — **nunca** entra no `assistant.liquid`.
- Editável sem deploy (via receptor / helper da conta), como toda conduta por conta.
- O tool é genérico: `@assistant.config.dig('gazetteer', 'bairros')` → filtra → formata.

> Tamanho: os 179 registros compactos ≈ 30–50 KB — cabem no JSONB sem entrar no prompt (só o tool lê).
> O JSON de 199 KB (`gazetteer-sinop.json`) é a fonte bruta; um passo de build extrai o subconjunto
> compacto pro `config`.

**Coordenadas:** ficam de fora do MVP. O `buscar_imovel` já aceita `bairro` como string (match `like`
no campo Bairro do Vista), então bairro→imóvel não precisa de lat/lng. Coords entram depois (campo
opcional por bairro, do geocoding da Fase 2) só se quisermos proximidade por centroide de bairro.

## Esqueleto (ilustrativo — Fase 2, segue o padrão `BasePublicTool`)

```ruby
class Captain::Tools::ConsultarBairroTool < Captain::Tools::BasePublicTool
  description '...'  # a descrição acima, sem exemplo copiável

  param :bairro,   type: 'string', desc: '...', required: false
  param :regiao,   type: 'string', desc: '...', required: false
  param :perfil,   type: 'string', desc: '...', required: false
  param :perto_de, type: 'string', desc: '...', required: false

  def perform(_tool_context, bairro: nil, regiao: nil, perfil: nil, perto_de: nil)
    base = @assistant.config&.dig('gazetteer', 'bairros')
    return 'Sem base de bairros configurada pra esta conta.' if base.blank?

    matches = filtrar(base, bairro:, regiao:, perfil:, perto_de:)
    return sem_match(bairro || regiao || perfil || perto_de) if matches.empty?

    formatar(matches.first(3))
  rescue StandardError => e
    Rails.logger.warn("[ConsultarBairroTool] #{e.message}")
    'Não consegui consultar o bairro agora.'
  end
end
```

## O que falta pra implementar (Fase 2, em ordem)

1. **Geocoding na VM** contra o acervo Vista → fecha os ~90 do long tail, valida região por coordenada,
   e revela quais bairros têm imóvel de fato (os que importam).
2. **Build** do subconjunto compacto (`gazetteer-sinop.json` → `config['gazetteer']` da conta 6).
3. **Implementar** `ConsultarBairroTool` + registrar no `tools.yml`.
4. **Injetar** o mapa mental no `config['instructions']` da conta 6 (via helper `tozi-prod`).
5. E2E na HML antes da conta 6 (produção), dentro da cerimônia de isolamento.
