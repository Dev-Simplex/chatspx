# QUALITY.md — Kit de Qualidade Padrão (instruções para IA)

> **Como usar:** copie este arquivo para a raiz do projeto (ou `docs/QUALITY.md`) e peça à IA:
> _"Aplica o kit de qualidade conforme o QUALITY.md, nível X"_.
> Referencie no CLAUDE.md do projeto com uma linha: `Qualidade: seguir docs/QUALITY.md`.

---

## 0. Classificação do projeto (decidir ANTES de instalar qualquer coisa)

| Nível | Quando | Aplicar |
|---|---|---|
| **1 — PROTÓTIPO** | Build-to-Learn, prova de conceito, vida < 1 mês | Só o Nível 1 |
| **2 — CLIENTE COM UI** | Projeto entregável com interface que importa | Níveis 1 + 2 |
| **3 — PRODUTO LONGO PRAZO** | Vai viver anos, lógica de negócio própria | Níveis 1 + 2 + 3 |

Se o nível não for óbvio, a IA DEVE perguntar antes de instalar ferramentas.
Stack não-JS (Rails, Python): manter os mesmos princípios com equivalentes (RSpec/pytest, Brakeman/Bandit, rubocop/ruff). O restante deste arquivo assume TypeScript/JavaScript.

---

## NÍVEL 1 — Piso (todo projeto, sem exceção)

### 1.1 TypeScript strict

```jsonc
// tsconfig.json (mínimo obrigatório)
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noFallthroughCasesInSwitch": true
  }
}
```

### 1.2 Lint + formatação — Biome

Projeto novo: `npm i -D @biomejs/biome && npx biome init`.
Projeto que JÁ usa ESLint+Prettier: manter (não migrar sem pedido explícito).

### 1.3 Testes unitários — Vitest

`npm i -D vitest`. Scripts: `"test": "vitest run"`, `"test:watch": "vitest"`.

### 1.4 Pre-commit — husky + lint-staged

```bash
npm i -D husky lint-staged && npx husky init
```

```json
// package.json
"lint-staged": {
  "*.{ts,tsx,js,jsx,json,css,md}": ["biome check --write --no-errors-on-unmatched"]
}
```

- `.husky/pre-commit` → `npx lint-staged`
- `.husky/pre-push` → `npm run typecheck && npm test` (typecheck não dá para escopar por arquivo staged — vai no push, não no commit)

### 1.5 Playwright smoke + fixture anti-erro (A REGRA MAIS IMPORTANTE)

Todo teste E2E DEVE falhar se aparecer erro de console, exceção de página ou HTTP 4xx/5xx não esperado. Isso pega a maior parte dos bugs que IA gera e não percebe.

```ts
// e2e/fixtures.ts
import { test as base, expect } from "@playwright/test";

// ruído conhecido que NÃO deve falhar o teste (manter curta e justificada)
const IGNORAR = [/favicon\.ico/, /analytics/, /hot-update/];

export const test = base.extend({
  page: async ({ page }, use) => {
    const erros: string[] = [];
    page.on("pageerror", (e) => erros.push(`pageerror: ${e.message}`));
    page.on("console", (msg) => {
      if (msg.type() === "error") erros.push(`console.error: ${msg.text()}`);
    });
    page.on("response", (res) => {
      if (res.status() >= 400 && !IGNORAR.some((rx) => rx.test(res.url()))) {
        erros.push(`HTTP ${res.status()}: ${res.request().method()} ${res.url()}`);
      }
    });
    await use(page);
    expect(erros, "Erros capturados durante o teste").toEqual([]);
  },
});
export { expect };
```

Todo arquivo E2E importa `test`/`expect` DESTE fixture, nunca direto de `@playwright/test`.
Smoke mínimo: 1 teste por fluxo vital (carregar home, login, ação principal) esperando por **âncora de conteúdo forte** (texto/elemento específico da tela pronta — nunca marcador de hidratação nem `networkidle`).

### 1.6 Zod nas bordas (código de produção, não teste)

Toda resposta de API externa e todo dado que cruza fronteira (RPC, banco → cliente) passa por schema Zod. Tipo declarado é hipótese; o schema é a prova.

```ts
const TarefaSchema = z.object({
  id: z.string(),
  // datas cruzam a borda como ISO string SEMPRE — normalizar Date→ISO no servidor
  due_date: z.string().datetime().nullable(),
});
export type Tarefa = z.infer<typeof TarefaSchema>;
// na borda: TarefaSchema.parse(dadoCru) — falhar ALTO, não silencioso
```

### 1.7 CI — GitHub Actions (gate autoritativo; hook local é só conveniência)

```yaml
# .github/workflows/quality.yml
name: quality
on: [push, pull_request]
jobs:
  checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 } # gitleaks precisa do histórico
      - uses: actions/setup-node@v4
        with: { node-version: 22, cache: npm }
      - run: npm ci
      - run: npx biome ci .
      - run: npm run typecheck
      - run: npm test
      - run: npm run build
      - name: Gitleaks (segredos)
        uses: gitleaks/gitleaks-action@v2
        env: { GITHUB_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
      - name: Semgrep (SAST)
        run: npx --yes semgrep@latest scan --config auto --error || pipx run semgrep scan --config auto --error
  e2e:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22, cache: npm }
      - run: npm ci
      - run: npx playwright install --with-deps chromium
      - run: npx playwright test
```

### 1.8 Review AI antes do humano

Antes de abrir PR: rodar `/code-review` (Claude Code) e, se instalado, `coderabbit review --agent` — corrigir os achados, só então pedir review humano.

---

## NÍVEL 2 — UI que importa (adicionar ao Nível 1)

### 2.1 Regressão visual — `toHaveScreenshot()` nos 3-5 fluxos principais

```ts
// playwright.config.ts
export default defineConfig({
  expect: { toHaveScreenshot: { maxDiffPixelRatio: 0.01, animations: "disabled" } },
});
```

```ts
await expect(page).toHaveScreenshot("dashboard.png", {
  mask: [page.getByTestId("relogio"), page.getByTestId("contador")], // TODO dado dinâmico
  fullPage: true,
});
```

**Regras anti-apodrecimento (obrigatórias):**
- MASCARAR todo dado derivado de relógio/contador — baseline sobre `now()` reprova sozinha quando vira o mês.
- Screenshot só do CHASSI (layout); dado variável valida-se por asserção estrutural, não por pixel.
- Capturar light E dark mode; viewport desktop (1280×720) e mobile (390×844).

### 2.2 Acessibilidade — axe em toda tela principal

```ts
import AxeBuilder from "@axe-core/playwright"; // npm i -D @axe-core/playwright

test("a11y dashboard", async ({ page }) => {
  await page.goto("/dashboard");
  await expect(page.getByRole("heading", { name: "Dashboard" })).toBeVisible(); // âncora forte ANTES do axe
  const { violations } = await new AxeBuilder({ page }).analyze();
  expect(violations).toEqual([]);
});
```

Limitação conhecida: axe pega ~30-40% das violações reais — é piso, não teto.

---

## NÍVEL 3 — Produto de longo prazo (adicionar aos Níveis 1 + 2)

### 3.1 Property-based — fast-check nas funções puras críticas

Alvo: cálculo, parsing, regras de data/preço/permissão. NÃO aplicar em CRUD trivial.

```ts
import fc from "fast-check"; // npm i -D fast-check

test("total nunca é negativo e é idempotente", () => {
  fc.assert(
    fc.property(fc.array(fc.record({ preco: fc.integer({ min: 0 }), qtd: fc.nat() })), (itens) => {
      const total = calcularTotal(itens);
      expect(total).toBeGreaterThanOrEqual(0);
      expect(calcularTotal(itens)).toBe(total); // determinístico
    }),
  );
});
```

Pense em INVARIANTES ("ordenar 2x = ordenar 1x", "parse(format(x)) = x"), não em exemplos.

### 3.2 Mutation testing — Stryker (CI noturno/incremental, NUNCA no pre-commit)

```bash
npm i -D @stryker-mutator/core @stryker-mutator/vitest-runner
```

```json
// stryker.config.json
{
  "testRunner": "vitest",
  "incremental": true,
  "mutate": ["src/dominio/**/*.ts", "!src/**/*.test.ts"],
  "thresholds": { "high": 80, "low": 60, "break": 50 }
}
```

Escopo: só os módulos core (`src/dominio`, regras de negócio). Mutante sobrevivente = teste com asserção vazia → corrigir o TESTE.

### 3.3 Opcional conforme necessidade
- **Lighthouse CI** — budget de Core Web Vitals quando performance for requisito.
- **k6** — teste de carga quando houver meta de usuários simultâneos.
- **Schemathesis** — fuzzing automático se o backend expõe OpenAPI.

---

## REGRAS PARA A IA (MUST / MUST NOT)

```
MUST: todo teste E2E usa o fixture anti-erro (1.5) — nunca @playwright/test direto
MUST: asserção verifica VALOR esperado, nunca só non-null/truthy/length
MUST: esperar âncora de conteúdo forte, nunca networkidle nem marcador de hidratação
MUST: mascarar dado dinâmico em screenshot; baseline só do chassi
MUST: dado que cruza borda passa por schema Zod que falha alto
MUST: rodar a Definition of Done abaixo e reportar resultado real (falha = falha)

MUST NOT: teste que espelha a implementação (tautológico — mutante sobreviveria)
MUST NOT: aprovar snapshot/baseline sem ler o diff
MUST NOT: silenciar erro de console adicionando à lista IGNORAR sem justificar em comentário
MUST NOT: instalar ferramenta de nível superior ao classificado sem perguntar
MUST NOT: pular hooks (--no-verify) ou desligar gate para "fazer passar"
```

## DEFINITION OF DONE do setup

```bash
npx biome ci .            # limpo
npm run typecheck         # limpo
npm test                  # verde
npm run build             # sucesso
npx playwright test       # verde, com fixture anti-erro ativo
git commit (arquivo teste) # pre-commit dispara lint-staged
# CI verde no primeiro push (incluindo gitleaks + semgrep)
```

---
*Fonte: vault SimplexOB — [[Padrao Pipeline de Qualidade Pre-Review com AI]] e [[Padrao Mutation e Property Testing contra teste fraco de IA]]. Atualizado 2026-08-12.*
