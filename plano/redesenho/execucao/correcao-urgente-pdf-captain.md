# ⛔ CORREÇÃO URGENTE DE PRODUÇÃO — ingestão de PDF do Captain

**Commit local: `5b0aa72161`** · nenhum push, nenhum deploy.

---

## Veredito: **herdado, não causado pelas ondas**

E a data é outra do que supúnhamos. **Não é 16/07, e não é o `b1c3c7812b`.**

Conferi o base **naquele commit e antes dele**: já era `def initialize` sem argumento nas
duas pontas. `b1c3c7812b` não pode ter introduzido o defeito — ele só acrescentou o hook
`api_key_config_name` e o `resolve_access_token`.

### A linha do tempo real, medida commit a commit sobre `homologacao`

| SHA | Data | Autor | O que aconteceu |
|---|---|---|---|
| `2eae1f0801` | **24/02/2026** | simplex | base ganha `initialize(account:)` **e** as duas subclasses ganham `super(account:)` — **consistente na época** |
| `72a58c9474` | 26/03/2026 | — | ainda consistente |
| **`cb0d3d999f`** | **31/03/2026** | simplex | **merge: homologacao → producao (upgrade v4.12.1)** — **quebra aqui** |

`cb0d3d999f` é um **merge**. O lado upstream (`38f8e1da85`) trouxe o base sem argumento; o
merge manteve as nossas subclasses chamando o contrato antigo. É a perda clássica de fork:
o arquivo do upstream venceu e os chamadores ficaram para trás.

Ancestral de `c06ba1824e` (base das ondas), de `homologacao` e do `HEAD`: **SIM nos três**.

### **São quatro meses e meio em produção, não um.**

---

## O impacto, sendo preciso

`crawl_job.rb:22` faz `Captain::Llm::PdfProcessingService.new(document).process`. O job
**re-lança** o erro (`rescue StandardError => e ... raise`). Então não é no-op silencioso:

- o documento **nunca chega a `:available`** na base de conhecimento do Captain;
- o Sidekiq **queima as retentativas** do job;
- a geração de FAQ a partir de documento (`PaginatedFaqGeneratorService`) cai igual.

---

## A chave resolvida — a checagem que foi pedida

**Continua exatamente a mesma de antes do `b1c3c7812b`.** Sem `api_key_config_name`
sobrescrito, `resolve_access_token` devolve `CAPTAIN_OPEN_AI_API_KEY`.

E é **deliberado, não herdado por acidente**: `b1c3c7812b` separou chave por propósito para
**eval** (`EVAL_OPEN_AI_API_KEY`) e **transcrição de áudio** (`AUDIO_OPEN_AI_API_KEY`).
Ingestão de PDF **não entrou** na separação. Ficou explícito em comentário **e travado por
teste**, para não voltar a ser acidente.

> Achado lateral, para você decidir: a versão de 24/02 (`2eae1f0801`) resolvia a chave por
> **conta**, via `Llm::AccountCredentialsResolver`, e o modelo por
> `captain_#{feature}_model`. O merge do v4.12.1 reverteu isso para configuração
> **installation-wide**. Se credencial OpenAI por conta era intencional no fork, ela se
> perdeu no mesmo merge — e isso é maior que este bug.

---

## O conserto

Padrão do `Messages::AudioTranscriptionService`, que o `b1c3c7812b` corrigiu na época:
`@account` atribuído **antes**, `super()` **sem argumento**.

Nenhuma das duas classes lia `@account` — usavam `document.account` / `document.account_id`
direto. A atribuição fica por consistência com a irmã e com o contrato do base; no
`paginated` ela ainda simplifica a chamada do `FeatureRouter`.

---

## Números

| Medida | Valor |
|---|---|
| **Vermelho antes** | **11 examples, 11 failures** (3 no `pdf` + 8 no `paginated` — **todos**) |
| **Verde depois** | **11 examples, 0 failures** |
| Teste novo contra o código quebrado | **10 examples, 6 failures** |
| **Portão final** | **28 examples, 0 failures** (contrato 10 + pdf 3 + paginated 8 + áudio 7) |
| `crawl_job` | 7 examples, 0 failures |
| Suíte `enterprise/captain/llm` | **69 → 58 failures** — exatamente as 11, e **nenhuma nova** |

As 58 restantes são as de `WebMock::NetConnectNotAllowedError`, pré-existentes.

---

## O teste que cobra o próximo

`spec/enterprise/services/llm/legacy_base_open_ai_service_contract_spec.rb`:

- **instancia todas as subclasses** de verdade;
- **varre `Llm::LegacyBaseOpenAiService.subclasses`** e reprova quem não declarar como se
  constrói — subclasse nova nasce coberta sem ninguém lembrar de adicioná-la;
- trava **qual chave** cada uma resolve.

### Por que o defeito durou 4,5 meses

**Os specs das duas classes estavam vermelhos o tempo todo.** Não faltava teste — faltava
alguém olhar. A suíte `enterprise/llm` carrega dezenas de falhas de WebMock (specs que
tentam alcançar `api.openai.com`), e **vermelho novo se perde dentro de vermelho velho**.

Por isso o arquivo novo não toca rede e não depende de fixture pesada: ele precisa ser
verde por padrão para que uma quebra seja visível.

> **Recomendação separada:** enquanto as 58 falhas de WebMock continuarem lá, essa suíte
> não serve de régua para ninguém. Vale um bloco só para zerá-las.
