# Deploy do nível 2 do Captador

Pacote de deploy da branch `feature/captador-nivel2`, que tem a integração nativa com o Captador (contrato em `docs/contratos/captador.md`). **Nada aqui foi aplicado.**

Quando rodar:
- depois do teste ponta a ponta com o Captador, no fim da Onda 3 do plano (`comercial-captador/pesquisa/25-plano-execucao.md`);
- com o "ok para subir" que o usuário já deu, primeiro na `.229`, com conferência, e depois nas outras VMs.

O processo é o do time (`.claude/commands/promover-pr.md`), sem atalho. O script `scripts/ops/captador-deploy.sh` só junta os passos específicos deste deploy. Por padrão ele imprime os comandos; executa de verdade só com `EXECUTAR=1`.

## 1. Como o código chega nas VMs hoje

| Etapa | Como é feito |
|---|---|
| Integração | PR para a `producao` e `gh pr merge <n> --merge --match-head-commit <sha>`. O merge é gate humano, depois do raio-X (`python3 scripts/ops/pr-raiox.py <n> --frota`) e da revisão. |
| Transporte | Da PRODUCAO (`.229`), que alcança o GitHub: `git bundle create rel.bundle producao --not <commit das VMs>`. Nas VMs, `git fetch rel.bundle producao && git merge --ff-only FETCH_HEAD`. Só a AGN alcança o GitHub; as outras respondem `could not read Username`. |
| Front | Build uma vez, no checkout principal da `.229`, com heap de 12288 MB. Depois vão para as VMs só os arquivos novos de `public/vite` (com `.gz`, porque o nginx usa `gzip_static`), extraídos por cima sem `--delete`. |
| Banco | `db:migrate` só se houver migration; `db:migrate:status` sem nenhum `down` sempre. |
| Restart | **Nenhum de dia.** O `chatwoot-restart-noturno.timer` reinicia às 20:00 de Cuiabá só as units (web e workers) que subiram antes de a branch andar, e aborta se houver migration pendente. O timer é reinstalado a cada deploy. |
| Janela proibida | 19:50 a 20:10 de Cuiabá (o timer pegaria o deploy no meio). |
| Clientes | TOZI e CDSOLAR entram só com OK explícito do usuário **a cada deploy**, por último. O OK vale também para a leitura por SSH (inclusive a do raio-X com `--frota`). |
| Legado | `deployment/deploy.sh` (`cwctl -U` com restart na hora) é reserva e não serve às VMs AWS, que não buscam do GitHub. O `deployment/panel/server.js` não é tocado. |

**Tempo fora do ar por VM:**
- de dia, nenhum: o Puma segue no código antigo até o restart;
- às 20:00, o restart das units. Na `.229`, com quatro units (web, worker, bulk, realtime), foi de 20:00:00 a "no ar, `/api` 200" em cerca de 30 s (`log/restart-noturno.log`, 24/09 20:00:30). Nas VMs AWS só há `web.1` e `worker.1`; o timer espera o `/api` até 3 min.

**Ordem das VMs:**
- 1º dia: PRODUCAO (`.229`), com conferência depois das 20:00.
- 2º dia: CATATAU → SENTINELA → FABRICA → AGN, uma por vez, e depois TOZI e CDSOLAR, se o usuário der o OK.
- A homologação `.232` segue a Fase 6 do `/promover-pr`.

## 2. Estado lido na `.229` (27/09/2026, só leitura)

| Item | Valor |
|---|---|
| Checkout | `/home/chatwoot/chatwoot`, branch `producao` em **`e4c385f5b3`** ("fix(conversas): resposta dada pelo WhatsApp do celular mostra icone do WhatsApp"); a branch andou em 26/09 18:02 UTC. É o mesmo commit da `origin/producao` e a base da feature (2 commits à frente, 0 atrás). |
| Árvore | 74 arquivos não rastreados, nenhum rastreado alterado além do `public/version.json`. **Nenhum colide** com os 24 arquivos novos da feature, então o `--ff-only` passa. |
| Serviços | `chatwoot-web.1`, `worker.1`, `worker.bulk` e `worker.realtime` ativos; o web subiu em 26/09 18:08 UTC, depois de a branch andar, então já serve o disco. |
| Timer | `enabled`. Últimas noites: 24/09 reiniciou (`/api` 200); 25/09 **abortou** por migration pendente; 26/09 reiniciou os workers. |
| Saúde | `/api` 200; `/spx/captador/v1/catalogo` **404** (esperado antes do deploy). |
| Journal e migrations | 0 erros no journal nas últimas 2 h; 0 migrations pendentes. |
| Disco | `/` com 886 GB, 55% usado, 385 GB livres. |
| Ferramentas | `gh` logado como Dev-Simplex, `pnpm`, `node`, `git`, e a chave das VMs AWS (`simplex.linux.pem`, 600). |
| Env | `FRONTEND_URL=https://chat.simplexsolucoes.com.br`; `RACK_ATTACK_ALLOWED_IPS` não definido. |
| Rede | `captador.spx.ia.br` já resolve na `.229` (Cloudflare). |

## 3. O que este deploy exige

- **Tamanho:** 41 arquivos, +2691/−1.
- **Sem migration e sem mudança no `Gemfile.lock` ou no `package.json`**, logo sem `bundle install` e sem `pnpm install`.
- **Com front** (`ContactPanel.vue` e o painel novo): exige o build de assets.
- **Ponto de risco: o boot.** Mudam `config/routes.rb` e `config/initializers/rack_attack.rb`, e entra um listener novo para todas as contas. Por isso a `.229` sobe primeiro e é conferida antes das outras.
- **Desligado por padrão:** nenhuma conta tem `captador_integration`. Até alguém ligar, o app não aparece em Integrações, `/spx/captador/*` responde 401 e o listener descarta tudo no primeiro filtro, feito em memória.

## 4. Roteiro

Tudo roda na `.229`, como `chatwoot`, em `/home/chatwoot/chatwoot`, com `S=scripts/ops/captador-deploy.sh`. Sem `EXECUTAR=1`, cada passo só imprime o que faria.

**0. Antes (qualquer hora, não muda nada)**
```bash
git fetch origin feature/captador-nivel2
bash $S ensaio              # merge, pacote, ff-only, revert e volta, em clones /tmp
bash $S verificar PRODUCAO  # o retrato do "antes"
```

**1. Integração (gate humano)**
```bash
EXECUTAR=1 bash $S integrar                 # abre o PR feature/captador-nivel2 -> producao
python3 scripts/ops/pr-raiox.py <PR> --frota
sha=$(gh pr view <PR> --json headRefOid --jq .headRefOid)
gh pr merge <PR> --merge --match-head-commit "$sha"
```

**2. Dia 1: PRODUCAO (`.229`)**
```bash
EXECUTAR=1 bash $S producao   # ff, assets + .gz, db:migrate:status zerado, timer e o pacote em /tmp/captador-deploy
# depois das 20:05 de Cuiabá:
bash $S verificar PRODUCAO
```
- O esperado é `/spx/captador/v1/catalogo: 401`, `/api: 200`, 0 erros no journal e no `production.log` e a última noite como "reiniciou".
- Também dá para conferir no navegador: a lista de Integrações abre e o app Captador **não** aparece (a chave está desligada).
- Com o OK do usuário para este restart, dá para não esperar as 20:00: `EXECUTAR=1 REINICIAR_OK=PRODUCAO bash $S producao --reiniciar-agora`, e `verificar` um minuto depois.

**3. Dia 2: as outras, uma por vez (fora de 19:50 a 20:10)**
```bash
EXECUTAR=1 bash $S vm CATATAU    # pacote, ff-only, assets, migrate:status, timer; sem restart
EXECUTAR=1 bash $S vm SENTINELA
EXECUTAR=1 bash $S vm FABRICA
EXECUTAR=1 bash $S vm AGN
EXECUTAR=1 bash $S vm TOZI --incluir-tozi         # só com o OK do usuário deste deploy
EXECUTAR=1 bash $S vm CDSOLAR --incluir-cdsolar   # idem
# depois das 20:05:
bash $S verificar CATATAU SENTINELA FABRICA AGN   # e TOZI/CDSOLAR com --incluir-*, se foram
```
Se uma VM falhar no `ff-only`, ela divergiu (tem commit só dela): pare, faça o backup do passo 3 da Fase 6 do `/promover-pr` e não force.

**4. Homologação (`.232`):** Fase 6 do `/promover-pr`. Alinhe a `homologacao` com a `producao`, extraia o mesmo tgz de assets e deixe o restart com o timer (a `.232` tem clientes).

## 5. Volta

1. **Na hora, sem deploy:** Super Admin → conta → desmarcar **Captador integration enabled** e apagar o hook em Integrações → Captador. O efeito é imediato: `/spx/captador/*` responde 401, o painel some e nenhum evento sai.
2. **Código:**
   - `EXECUTAR=1 bash $S reverter <sha do merge>` cria `revert/captador-nivel2` com `git revert -m 1` e abre o PR;
   - o merge do PR de revert é um gate humano;
   - depois, `producao` e `vm` como num deploy normal. A volta também tem front (o painel sai), então passa pelo build.
   - **Sem migration, não há schema para desfazer.** O que fica no banco é inofensivo: `accounts.settings.captador_integration`, o hook (o `HookListener` ignora `app_id` que não conhece), a label `captador` e as definições de atributo.
3. **Subir de novo depois de reverter:** reverta o revert. Um novo merge da feature não traz os commits de volta.

**Ensaio a seco da ida e da volta** (`bash $S ensaio`, 27/09, na base `e4c385f5b3`):
```
ida ok: base e4c385f5b3 -> merge a1ed794672 (pacote 76K, 41 arquivos)
volta ok: revert ceb0f1720a deixa a VM com a árvore de e4c385f5b3 (pacote 28K); sem migração a desfazer
```
Os SHAs do merge e do revert mudam a cada execução, porque o ensaio cria commits novos; o que conta são os dois `ok`.

O ensaio:
- faz o merge como o GitHub (commit com dois pais);
- cria o pacote e o aplica numa "VM" parada na base, que recusa o que não for fast-forward;
- faz o revert `-m 1` e confirma que a árvore da VM volta a ser byte a byte a da base.

## 6. O que ligar depois do deploy

A ordem vale para a conta de produção da Simplex. A homologação faz o mesmo numa conta de testes, não nas contas 3, 4 e 5.

1. **Chave por conta:** Super Admin → Accounts → a conta → **Captador integration enabled** (`accounts.settings.captador_integration`). Só nas contas que usam o Captador.
2. **Hook:** na conta, Configurações → Integrações → **Captador**.
   | Campo | Valor |
   |---|---|
   | Endereço do Captador | `https://captador.spx.ia.br` |
   | Chave da instância | a `instance_key` que a tela Conexões do Captador mostra para esta instância e conta |
   | Segredo compartilhado | gerado no Captador (no mínimo 32 caracteres); o mesmo valor fica cifrado lá |
   | Caixas liberadas | ids das caixas por onde o Captador pode abrir conversa, separados por vírgula |
   | Permitir login no Captador | marcar **só** na conta cujos usuários entram no Captador |
   Ao salvar, o `Crm::SetupJob` cria a label `captador` e os atributos `cnpj` e `captador_lead_id`.
3. **Rack::Attack: não mexer.**
   - Não é preciso pôr o IP do Captador em `RACK_ATTACK_ALLOWED_IPS`. O único limite geral por IP é `req/ip`, de 3000 pedidos por minuto, muito acima do que o Captador faz (login, envios, catálogo e reconciliação de hora em hora).
   - A safelist tiraria o IP de **todas** as regras, inclusive do `captador_login/email` (10 tentativas por e-mail a cada 15 min), que protege as senhas contra força bruta.
   - Revisar só se um lote de envio passar de 3000 pedidos por minuto.
4. **Rede:** a `.229` chama `https://captador.spx.ia.br` para os eventos e para o painel (timeout de 3 s); o DNS já resolve. Quando o Captador estiver no ar, conferir de lá com `curl -sI https://captador.spx.ia.br/healthz`.
5. **Caixas:**
   - oficial (Cloud) só abre conversa com modelo **aprovado**;
   - não oficial (WAHA) envia texto livre, com o risco ao número aceito pelo usuário;
   - para não virar "dois CRMs", a caixa e o time de prospecção não devem ter funil do ChatSPX.
6. **Conferência final:**
   - login no Captador com um usuário da conta;
   - envio para um número interno;
   - resposta pelo celular, que move o card;
   - painel na conversa com "Mover para…".
