# Plano Anti-OOM WAHA — VM cyaws (100.49.191.224)

> **Autor**: Orion (aiox-master) com squad @analyst + @architect + @devops
> **Data**: 2026-05-27
> **Contexto**: VM cyaws caiu 2 vezes em 2 dias (25/05 e 27/05). Investigação revelou que NÃO era memory leak — era bug do WAHA gows com placeholder `a.whatsapp.net` causando retry storm DNS quando recebe figurinhas.

---

## Causa raiz confirmada

**Bug:** Cada figurinha recebida disparava DNS lookup pra `a.whatsapp.net` (URL placeholder do Meta, sempre retornou NXDOMAIN). WAHA antigo tentava baixar de verdade → retry exponencial infinito → buffers acumulavam → OOM → VM travada.

**Evidência:** 11.389 erros `dial tcp: lookup a.whatsapp.net: no such host` no log do container.

**Fix oficial:** WAHA Plus **2026.5.1** (publicado 2026-05-26) — release notes literal:
> *"GOWS — Sticker download: drop placeholder a.whatsapp.net URL"*

## Estado atual

- Container: `devlikeapro/waha-plus:gows` (tag móvel, sem pin)
- VM: AWS t3.large (2 vCPU, 7.6 GB RAM, 4 GB swap)
- Sessões: 17 total / 14 WORKING / 3 FAILED (SPX, GabrielTecnologia, WillianCampo precisam QR)
- Mem idle WAHA: ~774 MB / Memória total stack idle ~2.2 GB
- Co-host: Coolify v4 + Postgres + Redis + Traefik

## Validação de sizing (doc oficial WAHA)

- GOWS usa ~60 MB/sessão → 14 sessões × 60 MB = ~840 MB baseline
- Mínimo recomendado WAHA: 2 vCPU + 4 GB → temos com folga
- WAHA não recomenda restart programado — fix do leak veio na 2026.5.1
- Pra começar a separar VM, só após ~50 sessões

✅ **t3.large basta**, NÃO precisa upgrade de instance type.

---

## Plano de execução (3 prioridades)

### 🔴 P0 — Janela única (~3 min downtime WAHA)

Aplicar TUDO via Coolify API PATCH no `docker_compose_raw` do service WAHA + `POST /api/v1/deploy?force=true`:

1. **Upgrade imagem**: `devlikeapro/waha-plus:gows` → `devlikeapro/waha-plus:2026.5.1`
   - Pinnar versão exata (NÃO usar `:latest` nem `:gows`)
   - Sessões persistem (Postgres external)

2. **Defesa em profundidade — `extra_hosts`**:
   ```yaml
   extra_hosts:
     - "a.whatsapp.net:127.0.0.1"
   ```
   - DNS falha em ms (connection refused) em vez de timeout segundos
   - Caso bug volte em versão futura

3. **Memory limit cgroup** no container WAHA:
   ```yaml
   mem_limit: 3g
   memswap_limit: 3584m
   ```
   - Se algo vazar futuramente, só WAHA apanha (kernel mata e restarta), não derruba SSH/Coolify

4. **Healthcheck Docker** apontando para `/health` (endpoint oficial Plus):
   ```yaml
   healthcheck:
     test: ["CMD-SHELL", "curl -fsS http://localhost:3000/health || exit 1"]
     interval: 30s
     timeout: 10s
     retries: 3
     start_period: 60s
   restart: unless-stopped
   ```

### 🟡 P1 — Mesma janela (env vars produção)

5. `WAHA_LOG_FORMAT=JSON` — logs estruturados
6. `WAHA_LOG_LEVEL=info` — evita debug em prod
7. `WAHA_PRINT_QR=False` — reduz I/O console
8. (Opcional) Trocar `WAHA_API_KEY` plain por `sha512:` hash

### 🟢 P2 — Pode rodar agora (zero downtime)

9. **Journal persistente** (`/var/log/journal/`, limit 500 MB):
   ```bash
   sudo mkdir -p /var/log/journal
   sudo sed -i 's/^#\?Storage=.*/Storage=persistent/;s/^#\?SystemMaxUse=.*/SystemMaxUse=500M/' /etc/systemd/journald.conf
   sudo systemctl restart systemd-journald
   ```

10. **sysstat / sar 1min** — métricas históricas:
    ```bash
    sudo apt install -y sysstat
    sudo sed -i 's|5-55/10|*/1|' /etc/cron.d/sysstat
    sudo systemctl enable --now sysstat
    ```

11. **earlyoom** — mata processo top antes do kernel travar:
    ```bash
    sudo apt install -y earlyoom
    sudo tee /etc/default/earlyoom >/dev/null <<'EOF'
    EARLYOOM_ARGS="-r 60 -m 8 -s 5 --avoid '(^|/)(systemd|sshd|dockerd|containerd)$' --prefer '(^|/)(node|waha|postgres)$' -N"
    EOF
    sudo systemctl enable --now earlyoom
    ```

12. **Watchdog cron** WAHA — autorestart se `/health` falhar 3× consecutivas:
    ```bash
    sudo tee /usr/local/bin/waha-watchdog.sh >/dev/null <<'EOF'
    #!/bin/bash
    F=/var/run/waha-fail.count
    if curl -fsS --max-time 8 http://localhost:3000/health >/dev/null; then
      echo 0 > "$F"
    else
      N=$(( $(cat "$F" 2>/dev/null || echo 0) + 1 ))
      echo $N > "$F"
      if [ $N -ge 3 ]; then
        docker restart $(docker ps --filter name=waha --format '{{.Names}}' | head -1)
        echo 0 > "$F"
        logger -t waha-watchdog "RESTARTED waha after 3 failures"
      fi
    fi
    EOF
    sudo chmod +x /usr/local/bin/waha-watchdog.sh
    echo "*/2 * * * * root /usr/local/bin/waha-watchdog.sh" | sudo tee /etc/cron.d/waha-watchdog
    ```

13. **Alerta SMTP RAM < 1 GB**:
    ```bash
    sudo apt install -y msmtp msmtp-mta
    # /etc/msmtprc com SMTP chatspx.app
    sudo tee /usr/local/bin/mem-alert.sh >/dev/null <<'EOF'
    #!/bin/bash
    AVAIL=$(free -m | awk '/^Mem:/ {print $7}')
    if [ "$AVAIL" -lt 1024 ]; then
      TOP=$(ps aux --sort=-%mem | head -6)
      printf "Subject: [cyaws] RAM baixa %sMB\n\n%s\n\n%s\n" "$AVAIL" "$(free -h)" "$TOP" \
        | msmtp ederson.ricieri@gmail.com
    fi
    EOF
    sudo chmod +x /usr/local/bin/mem-alert.sh
    echo "*/5 * * * * root /usr/local/bin/mem-alert.sh" | sudo tee /etc/cron.d/mem-alert
    ```

14. **EBS daily snapshot** via AWS Backup (~$1/mês para volume 26 GB) — RTO <10 min.

---

## REMOVIDO do plano (não justifica)

- ❌ **Cron restart preventivo 12h** — não é prática oficial WAHA; 2026.5.1 corrige memory leak no changelog
- ❌ **Upgrade VM m6i.large** — overkill, t3.large folgado pra 14 sessões
- ❌ **Separar Coolify em outra VM** — 17 sessões cabem confortável; só após ~50

---

## Validação pós-aplicação

Após P0 estar aplicado:

```bash
# Confirmar versão correta no container
ssh ... "docker inspect waha-... --format '{{.Config.Image}}'"
# Esperado: devlikeapro/waha-plus:2026.5.1

# Validar healthcheck
ssh ... "docker ps --filter name=waha --format '{{.Names}} {{.Status}}'"
# Esperado: (healthy)

# Conferir extra_hosts dentro do container
ssh ... "docker exec waha-... cat /etc/hosts | grep whatsapp.net"
# Esperado: 127.0.0.1  a.whatsapp.net

# Monitorar 1 hora: log de erro a.whatsapp.net deve zerar
ssh ... "docker logs --since 1h waha-... 2>&1 | grep -c 'a.whatsapp.net'"
# Esperado: 0 (era ~11k antes do fix)

# Memória estável
ssh ... "docker stats --no-stream | grep waha"
# Esperado: < 1.5 GB sustentado
```

---

## Fontes de pesquisa

- [WAHA Changelog 2026.5.1](https://waha.devlike.pro/docs/overview/changelog/) (fix oficial)
- [WAHA Scaling docs](https://waha.devlike.pro/blog/waha-scaling-how-to-handle-500-sessions/)
- [WAHA Observability](https://waha.devlike.pro/docs/how-to/observability/)
- [GOWS Memory Leak #1708](https://github.com/devlikeapro/waha/issues/1708) (workaround comunidade)
- [Coolify Redis bug #5741](https://github.com/coollabsio/coolify/issues/5741)
- [earlyoom](https://github.com/rfjakob/earlyoom)
- [systemd-oomd PSI guide](https://dev.to/lyraalishaikh/stop-linux-memory-death-spirals-early-practical-systemd-oomd-with-psi-and-cgroup-policy-369j)

---

## Histórico de incidentes

| Data | Sintoma | Causa identificada agora |
|------|---------|--------------------------|
| 2026-05-25 ~17:30 UTC | VM cyaws inacessível | Retry storm `a.whatsapp.net` (não OOM gradual como suspeito antes) |
| 2026-05-27 ~15:17 UTC | VM cyaws inacessível | Mesmo bug — confirmado com 11k erros no log |

Após upgrade 2026.5.1, esses crashes não devem repetir.
