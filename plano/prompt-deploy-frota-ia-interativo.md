# PROMPT DE DEPLOY — `producao` @ `c97ce3b8e` (WhatsApp interativo + modo-antigo)

> **FRONT-ONLY. ZERO migration. Dormente** (motor Flow off por conta → nenhum cliente muda até ligar `flows_engine`).
> Ordem: **.229 (canário) → valida → resto da frota.** Tozi via bundle. FABRICA fora.

## ⚡ Jeito mais rápido (mecanismo do time) — RODAR DE DENTRO DA .229
```bash
ssh chatwoot@192.168.8.229          # (ou pelo painel)
cd /home/chatwoot/chatwoot
./deployment/deploy.sh producao     # fan-out: .229 + CATATAU + SENTINELA + ALTERNATIVO (Tozi comentado, FABRICA fora)
```
⚠️ **CUIDADO com o `deploy.sh`:** ele usa `NODE_OPTIONS=--max-old-space-size=4096` no precompile — a nossa lição é **8192** (4096 pode dar **OOM silencioso** → bundle velho → front quebrado). Depois do deploy, **conferir o mtime do `public/vite/.vite/manifest.json` em cada VM** (tem que ser novo). Se suspeitar de OOM, repetir o precompile com 8192. O script também roda `db:migrate` (no-op aqui — zero migration).

## Contexto (o que sobe)
F1 nó "Enviar opções (lista/botões)" · F2 nó "Aguardar resposta" (loop escolhe→ramifica→ação, ex. transferir time) · F3 nós "Enviar botão de link", "Pedir localização", "Enviar formulário (Flow)" · **modo-antigo: seção que reexibe as automation_rules (ver/desligar/editar/excluir)**. Testado em homolog com **mensagens WhatsApp reais** (SimplexIA), rspec 123/0, vitest 83+15.

⚠️ É **front** → **precisa precompile**. **NÃO rodar `db:migrate`** (zero migration). Baixo risco: aditivo + dormente + rollback trivial.

---

## PASSO 1 — Puxar o código (.229 primeiro)
```bash
cd /home/chatwoot/chatwoot           # ajustar path do box
git fetch origin
git checkout producao
git pull --ff-only origin producao
git rev-parse --short HEAD           # DEVE imprimir: 40239f757
```
Se `pull --ff-only` falhar (box divergido/commit local) → **PARE e investigue**, não force.

## PASSO 2 — Precompile do front (o exit 0 MENTE no OOM — confira o manifest)
```bash
stat -c '%y' public/vite/.vite/manifest.json     # mtime ANTES
NODE_OPTIONS=--max-old-space-size=8192 RAILS_ENV=production bundle exec rake assets:precompile
stat -c '%y' public/vite/.vite/manifest.json     # mtime tem que ser AGORA (novo)
```
mtime não mudou = OOM silencioso → refaça. Manifest ~200KB+.

## PASSO 3 — Restart
```bash
sudo systemctl restart chatwoot.target
```

## PASSO 4 — Smoke test (.229)
- Site carrega, console do browser sem erro de JS/import.
- **Configurações → Automação → (abrir/criar no canvas)**: a paleta mostra os nós novos em MENSAGENS ("Enviar opções (lista/botões)", "Enviar botão de link", "Pedir localização", "Enviar formulário (Flow)") e em LÓGICA ("Aguardar resposta"). Nada de comportamento diferente pra quem não usa (motor dormente).

✅ **.229 OK → propaga pra frota.** ❌ **Quebrou → rollback (fim).**

---

## PASSO 5 — Frota (repetir 1–4 em cada VM)
- **Boxes com GitHub** (.229, catatau, sentinela, AGN…): mesmos comandos.
- **Tozi (.109):** sem credencial GitHub → **git bundle** (gera bundle do `producao` numa máquina com cred → `scp` → aplica no box → precompile → restart).
- **FABRICA (3.87.182.184):** **PULAR** (divergida).

---

## ATIVAR num cliente (passo SEPARADO, depois do deploy)
Deploy ≠ ligado. Pra um cliente usar os nós interativos:
1. Habilitar o motor Flow na conta: `rake flows:enable_engine ACCOUNT_ID=<id>` (ou setar `internal_attributes['flows_engine_enabled']=true`).
2. A conta precisa de uma inbox **WhatsApp Cloud oficial** (provider `whatsapp_cloud`). Em WAHA o caminho interativo oficial não se aplica.
3. Interativo só entrega **dentro da janela de 24h** (cliente falou <24h) — fora dela, WhatsApp exige template.

## ROLLBACK (trivial — front-only, zero migration)
```bash
git reset --hard fbbac1763
NODE_OPTIONS=--max-old-space-size=8192 RAILS_ENV=production bundle exec rake assets:precompile
sudo systemctl restart chatwoot.target
```
