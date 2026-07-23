# PROMPT DE DEPLOY — `producao` @ `fbbac1763` (realtime + canvas)

> Passar na **.229 (produção interna)** primeiro como canário; se OK, propagar pra frota.
> **FRONT-ONLY. ZERO migration. ZERO backend.**

## Contexto (o que sobe)
1. **Correção do banner "Desconectado"** — reconecta ao voltar de aba/foco + aviso offline escalonado (fim do banner preso).
2. **Remediação do canvas de automação** — blockers, paridade, a11y, testes. **Dormant**: só ativa com `flows_engine` ligado por conta (off por padrão) → **zero mudança visível pro cliente** até alguém habilitar. (De brinde, corrige os blockers B1/B2/M1 que estavam na prod.)

⚠️ É **front** → **precisa precompile**. **NÃO rodar `db:migrate`** (não tem migration).

---

## PASSO 1 — Puxar o código (.229)
```bash
cd /home/chatwoot/chatwoot           # ajustar se o path do box for outro
git fetch origin
git checkout producao
git pull --ff-only origin producao
git rev-parse --short HEAD           # DEVE imprimir: fbbac1763
```
Se `pull --ff-only` **falhar** (box divergido / com commit local) → **PARE e investigue**, não force.

## PASSO 2 — Precompile do front (o exit 0 MENTE no OOM — confira o manifest)
```bash
stat -c '%y' public/vite/.vite/manifest.json     # anota o mtime ANTES
NODE_OPTIONS=--max-old-space-size=8192 RAILS_ENV=production bundle exec rake assets:precompile
stat -c '%y' public/vite/.vite/manifest.json     # mtime tem que ser AGORA (novo)
```
Se o mtime **não mudou** = OOM silencioso (bundle velho) → refaça o precompile. Manifest esperado ~200KB+.

## PASSO 3 — Restart
```bash
sudo systemctl restart chatwoot.target
```

## PASSO 4 — Smoke test (.229)
- Site carrega (sem tela branca), console do browser **sem erro de import/JS**.
- **Configurações → Automação** abre normal (canvas dormant → UI antiga aparece).
- (Opcional) Perde a rede 8s: pill "Reconectando…" escala pra barra no topo e **some** ao voltar.

✅ **.229 OK → propaga pra frota.** ❌ **Quebrou → rollback (fim do doc).**

---

## PASSO 5 — Frota (repetir PASSO 1–4 em cada VM cliente)
- **Boxes com GitHub** (.229, catatau, sentinela, AGN, etc.): mesmos comandos.
- **Tozi (.109)**: **sem credencial GitHub** → deploy via **git bundle** (gera bundle do `producao` numa máquina com cred → `scp` → `git pull` do bundle no box) → precompile → restart.
- **FABRICA (3.87.182.184)**: **PULAR** — divergida, não deployar às cegas.

---

## ROLLBACK (trivial — front-only, zero migration)
```bash
git reset --hard 42e356b8e
NODE_OPTIONS=--max-old-space-size=8192 RAILS_ENV=production bundle exec rake assets:precompile
sudo systemctl restart chatwoot.target
```
