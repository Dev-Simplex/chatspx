# ⚓ Almirante — MCP de deploy da frota ChatSPX (100% Go)

Plataforma de deploy onde o dev fala **natural** no Claude Code (*"atualiza a tozi"*, *"reinicia a fábrica"*, *"sobe em todas"*) e o sistema executa com segurança. **A IA propõe → o humano autoriza → o sistema registra.**

Reescrita em Go da espec validada em `deployment/deploy-mcp/` (TS/Bash). Binário único estático, SSH puro, SDK MCP oficial.

## Estrutura

```
cmd/almiranted/        agente por-VM (executa o deploy faseado; gate por arquivo-token)   ✅ feito+testado
cmd/almirante-mcp/     MCP server (lado dev, stdio; SO le e SO propoe)                     ✅ feito+testado (mock)
cmd/almirante-control/ dispatcher REST (RBAC + anti-self-review + SSH transport)            ✅ feito+testado
internal/types/        tipos compartilhados
internal/safety/       classificacao destrutiva (denylist 20260330120000) + anti-injecao   ✅ testado
internal/fleet/        inventario fleet.json + grupos (aws/proxmox/critical/...)
internal/audit/        log append-only com hash-chain (imutavel)
internal/deploy/       pipeline faseado + gate + health real + rollback (o cwctld em Go)    ✅ testado (-race)
internal/ssh/          transporte SSH com knownhosts (HostKeyCallback; fix bug #3)          ✅ feito
internal/control/      store concorrente + RBAC + anti-self-review (fix bug #1)             ✅ testado
internal/mock/         dados deterministicos das 7 VMs (ALMIRANTE_MOCK=1)
```

## Rodar a demo (mock — zero rede, zero SSH, zero risco)

```bash
cd deployment/almirante
make build          # gera bin/almirante-mcp e bin/almiranted (estaticos)
make race           # roda TODOS os testes com -race
make demo           # sobe o MCP em mock
```

Plugar no Claude Code: copie `.mcp.json.example` → `.mcp.json`. Depois é só conversar:
*"qual o status da tozi?"* · *"tem migration pendente na tozi?"* · *"prepara o deploy da homologação"*.

## Tools (MCP) — feitas

`almirante_fleet_status`, `almirante_vm_status`, `almirante_vm_health`, `almirante_migration_status`,
`almirante_git_diff`, `almirante_deploy_history`, `almirante_whoami`, `almirante_propose_deploy_vm`,
`almirante_propose_deploy_all`, `almirante_propose_restart_vm`.
> As demais tools do catálogo (28) seguem o mesmo padrão — adição mecânica.

## Agente `almiranted` (na VM) — subcomandos

`current · health · migrate-status · plan <sha> · enqueue <sha> <actor> · approve <sha> <by> · deploy <sha> [--backup-done] · restart <unit> · rollback`

Contrato de deploy (sempre `RAILS_ENV=production`): `checkout → bundle → pnpm → assets:precompile → db:migrate → restart → health real → rollback automático se falhar`. Migration destrutiva **bloqueia** sem backup confirmado.

## Segurança (já no código)

- MCP **só lê e só propõe** — não existe tool de deploy/restart/approve.
- Gate por **arquivo-token** no agente: `deploy`/`restart` recusam sem aprovação humana; TTL conta da aprovação.
- Classificação destrutiva **server-side** (denylist + heurística), nunca no LLM.
- **Anti-injeção** (`AssertSafeArg`) aplicado também dentro do agente (defense-in-depth).
- Auditoria **hash-chain** (detecta adulteração).

## Status / próximos passos

- ✅ **Fase 1** (agente + núcleo) — compila, `go vet` limpo, testes `-race` verdes.
- ✅ **Fase 2** — MCP server (**29 tools**) + **dispatcher control** (RBAC + anti-self-review + freeze/cancel reais) + **internal/ssh com knownhosts**. 3 bugs do TS endereçados: #1 anti-self-review + `requested_by` do token, #3 knownhosts fail-closed, race do store (mutex).
- ✅ **Wiring real** — MCP fala HTTP com o control (`ALMIRANTE_MOCK=0` + `ALMIRANTE_CONTROL_URL`); testado ponta-a-ponta incl. freeze/unfreeze/cancel (`TestRealModeWiring`).
- ✅ **Painel offline** — `web/index.html` (Vue 3 + Tailwind **vendorizados** em `web/vendor/`), embutido via `go:embed`, servido em `/`: fleet overview + fila de aprovação + histórico. Zero CDN em runtime.
- ✅ **Release/CI** — `.goreleaser.yaml` (binários estáticos multi-arch, version via ldflags — `almiranted version` confirma) + `ci/almirante.yml` (template GitHub Actions) + `scripts/install-almiranted.sh` (Fase 0).
- ✅ **Código completo.** Tudo `go build`/`go vet`/`go test -race` verde. Resta apenas: copiar `ci/almirante.yml` → `.github/workflows/` se quiser CI ativo; e a Fase 0 abaixo.
- 🔴 **Fase 0 (humana, pré-req do modo real):** sudoers (`almiranted` como chatwoot + units web/worker), chave de transporte forced-command, popular known_hosts, instalar `almiranted` nas VMs (use `scripts/install-almiranted.sh`). Nada disso foi tocado — produção intacta.
