# PROMPT — Restart SEGURO do Sidekiq (e Puma) no homolog para ativar os PDFs de relatório

> Ambiente: VM homolog `192.168.8.232`, usuário `chatwoot`, app em `/home/chatwoot/chatwoot`, branch `nicolas`, `RAILS_ENV=production`.
> **Quem executa:** um operador humano. O `sudo` aqui **exige senha** (não dá para automatizar). Um agente NÃO consegue rodar os `systemctl restart`.
> **Objetivo:** fazer o processo em execução carregar o código novo dos PDFs de relatório (job, service, resolver, templates, helpers, rota e controller). **Sem alterar uma linha de código.**

---

## ⚠️ Por que um restart é necessário

O homolog roda em **produção** (Rails faz *eager load* e cacheia classes e templates no boot). Os processos atuais subiram há **~1 dia e 17h** — **antes** do código dos PDFs existir. Resultado: o Sidekiq não conhece `Reports::PdfExportJob` / templates novos, e o Puma não conhece a **rota** nem o **controller** novos. Só um restart recarrega isso.

**Atenção (corrige o pedido original):** restartar **só o Sidekiq não basta**. O botão "Baixar PDF" faz `POST` para `/api/v1/accounts/:id/report_pdf_exports`, que vive no **Puma** (`chatwoot-web.1.service`). Com o Puma velho, esse POST dá **404** e o job nunca chega ao Sidekiq. Para a feature funcionar ponta a ponta é preciso reiniciar **os dois** serviços:

| Serviço | Unit systemd | Carrega o quê (do PDF) |
|---|---|---|
| **Sidekiq** (o que você pediu) | `chatwoot-worker.1.service` | job, service, resolver, **templates**, helpers |
| **Puma** (companheiro obrigatório) | `chatwoot-web.1.service` | rota `report_pdf_exports`, controller, `Account#report_pdf_exports` |

> Esta operação **sobrepõe** a regra de frota "não reiniciar" — só porque **você (operador) autorizou explicitamente** este restart no homolog.

---

## ✅ Revisão de segurança (já feita — pode confiar)

- Todos os arquivos novos passam em `ruby -c` (**Syntax OK**): model, controller, job, service, resolver, `PdfAssetHelper`, `PdfChartHelper`.
- As únicas mudanças de backend que o restart ativa, além dos arquivos novos, são **mínimas e coesas**:
  - `app/models/account.rb`: **+1 linha** → `has_many :report_pdf_exports, dependent: :destroy_async`
  - `config/routes.rb`: **+1 linha** → `resources :report_pdf_exports, only: %i[create show]`
- A migration `20260609120000_create_report_pdf_exports` **já está aplicada** no DB de produção do homolog → o model funciona no boot.
- Jobs **enfileirados ficam no Redis** e sobrevivem ao restart; o Sidekiq está **`[0 of 52 busy]`** (ocioso) agora — momento limpo para reiniciar, sem interromper job em andamento.

---

## 🚫 O que NÃO fazer (manter não-destrutivo)

- ❌ Não editar código, não `git pull`, `git checkout`, `git stash`, `git reset`.
- ❌ Não rodar `db:migrate`, `bundle install`, `yarn/pnpm/vite build` (assets já buildados).
- ❌ Não rodar `systemctl daemon-reload` (nenhum arquivo de unit mudou).
- ❌ Não tocar em **PostgreSQL, Redis ou Nginx** — só os 2 serviços do app.
- ❌ Não reiniciar com job em andamento (confira `busy = 0` no passo 0).

---

## Passo 0 — Pré-voo (somente leitura; valida o código novo ANTES de tocar no daemon)

Rode como usuário `chatwoot`, dentro de `/home/chatwoot/chatwoot`:

```bash
cd /home/chatwoot/chatwoot

# 0.1 — branch certa e árvore com os arquivos do PDF
git branch --show-current        # deve ser: nicolas
git status --porcelain | grep -iE 'report_pdf|reports/pdf' | head

# 0.2 — Sidekiq ocioso? (precisa mostrar "[0 of 52 busy]")
ps -eo cmd | grep -E 'sidekiq 7' | grep -v grep

# 0.3 — PRÉ-VOO SEM ESCRITA: as classes e templates novos carregam em produção?
RAILS_ENV=production dotenv bundle exec rails runner '
  %w[ReportPdfExport Reports::PdfExportJob Reports::PdfExportService Reports::PdfDataResolver Reports::PdfChartHelper Reports::PdfAssetHelper].each(&:constantize)
  %w[nps csat bot conversations overview sla agent inbox team label].each { |t|
    raise "template ausente: #{t}" unless Rails.root.join("app/views/reports/pdf/#{t}.html.erb").exist? }
  puts "PREFLIGHT_OK: classes e templates carregam"
'
```

➡️ **Só prossiga se o passo 0.3 imprimir `PREFLIGHT_OK`.** Se der erro de load aqui, **não reinicie** — o daemon entraria em crash-loop (`Restart=always`, `RestartSec=1`). Investigue o erro primeiro.

**(Recomendado) Prova ponta a ponta sem mexer no daemon** — gera um PDF real no processo atual (escreve **1 registro** de export na conta de dev #1; reversível):

```bash
RAILS_ENV=production dotenv bundle exec rails runner '
  e = Account.find(1).report_pdf_exports.create!(report_type:"nps", filters:{"since"=>"2026-01-01","until"=>"2026-06-08"})
  Reports::PdfExportJob.perform_now(e.id); e.reload
  puts "SMOKE: status=#{e.status} size=#{e.file_size} sha=#{e.sha256.to_s[0,8]}"
  # limpeza opcional: e.file.purge; e.destroy
'
```
➡️ Esperado: `SMOKE: status=completed size=<bytes>`. Isso **prova** que o código novo roda — o restart só faz o daemon passar a usar esse mesmo código.

---

## Passo 1 — Restart do Sidekiq (o que você pediu)

```bash
sudo systemctl restart chatwoot-worker.1.service
```
systemd manda `SIGTERM` → Sidekiq para de pegar jobs novos e finaliza os em andamento (`TimeoutStopSec=30`) → sobe de novo. Verifique:

```bash
systemctl status chatwoot-worker.1.service --no-pager
sudo journalctl -u chatwoot-worker.1.service -n 40 --no-pager   # procurar erro de boot; deve subir limpo
```
➡️ Esperar `active (running)`, PID novo, sem exceção no log.

---

## Passo 2 — Restart do Puma (obrigatório p/ a rota/endpoint novos)

> Reinicia o web → a UI fica indisponível por ~20–40s enquanto os 7 workers sobem (`bin/rails server` em produção). Faça num momento de baixo uso.

```bash
sudo systemctl restart chatwoot-web.1.service
systemctl status chatwoot-web.1.service --no-pager
sudo journalctl -u chatwoot-web.1.service -n 40 --no-pager
```
➡️ Esperar `active (running)` e boot sem erro.

*(Alternativa de um comando só, reinicia os dois juntos: `sudo systemctl restart chatwoot.target` — pelos `PartOf=chatwoot.target`. Prefira sequencial: se o worker falhar, a UI continua no ar.)*

---

## Passo 3 — Verificação final (ponta a ponta)

```bash
# processos novos (etime baixo, sidekiq ocioso de novo)
ps -eo pid,etime,cmd | grep -E 'sidekiq 7|puma 6' | grep -v grep
```
Depois, **na interface**: **Relatórios → NPS → "Baixar PDF"** → deve baixar um PDF válido. Isso confirma os dois lados (rota no Puma + job no Sidekiq) ativos. Teste mais um (ex.: CSAT) por garantia.

---

## Se algo der errado (rollback)

- Unit em `activating (auto-restart)` em loop → houve erro de boot. Veja a causa:
  ```bash
  sudo journalctl -u chatwoot-worker.1.service -n 120 --no-pager
  ```
- **Não** tente "consertar" com `git checkout`/`stash` — o código foi verificado (passo 0). Uma falha de boot aqui seria ambiental (gem/env/Redis), não o código do PDF. Diagnostique pelo log antes de qualquer outra ação.
- Nenhum job é perdido: enfileirados estão no Redis; em andamento (se houvesse) são reprocessados pelo Sidekiq.

---

## Comandos prontos (resumo copiável)

```bash
cd /home/chatwoot/chatwoot
git branch --show-current
ps -eo cmd | grep -E 'sidekiq 7' | grep -v grep                     # confirmar [0 of 52 busy]
RAILS_ENV=production dotenv bundle exec rails runner '%w[ReportPdfExport Reports::PdfExportJob Reports::PdfDataResolver].each(&:constantize); puts "PREFLIGHT_OK"'

sudo systemctl restart chatwoot-worker.1.service                    # Sidekiq
systemctl status chatwoot-worker.1.service --no-pager

sudo systemctl restart chatwoot-web.1.service                       # Puma
systemctl status chatwoot-web.1.service --no-pager

ps -eo pid,etime,cmd | grep -E 'sidekiq 7|puma 6' | grep -v grep    # validar PIDs novos
# por fim: Relatorios -> NPS -> "Baixar PDF" na UI
```
