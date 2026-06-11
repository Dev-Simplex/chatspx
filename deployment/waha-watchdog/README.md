# WAHA Watchdog

Watchdog **standalone** (bash + curl + jq) que vive **FORA do Rails**. Monitora o
processo WAHA e o status de cada sessao e, quando habilitado, aplica **restart de
sessao** — que **NAO pede QR** (a auth persiste em `/app/.sessions` ou no Postgres).

> Roda por padrao em **`ALERT_ONLY=true`**: so observa e alerta, sem reiniciar nada.
> Depois de validar a deteccao em producao, vire para `ALERT_ONLY=false` (ver
> [Ligar o auto-restart](#ligar-o-auto-restart-depois-do-periodo-alert_only)).

## Como funciona

A cada ciclo (~60s, via `.timer` systemd):

1. **Liveness** — `GET /ping`. Se falhar, trata como possivel crash-loop:
   espera a API voltar com backoff (`PING_RETRIES` x `PING_RETRY_DELAY`, dobrando).
   Se nao voltar, **alerta** e encerra o ciclo (nao tenta restart as cegas).
   Se voltar, segue para a checagem de sessoes.
2. **Status por sessao** — `GET /api/sessions?all=true`. Para cada sessao alvo:
   - status em `HEALTHY_STATUSES` (default `WORKING`) -> OK.
   - qualquer outro (`STOPPED`, `FAILED`, `STARTING` travado, ausente...) -> acao.
3. **Acao** — `POST /api/sessions/{name}/restart`. **Nunca** faz `logout`/`stop`
   definitivo; **nunca** apaga sessao. Restart reaproveita a sessao autenticada,
   por isso **nao dispara QR**.
4. **Inbound-gap monitor** (opcional, `INBOUND_GAP_MONITOR=true`) — **SO-ALERTA**.
   Le `GET /api/{session}/chats/overview` e compara o timestamp do ultimo inbound
   entre execucoes. Sem avanco por `INBOUND_GAP_THRESHOLD`s -> alerta (sem reiniciar).
   Serve para tunar deteccao de "freeze" silencioso no futuro.

### Protecoes contra restart-storm

- **COOLDOWN_SECONDS** — espera minima entre restarts da MESMA sessao.
- **MAX_RESTARTS_PER_WINDOW** dentro de **RESTART_WINDOW_SECONDS** — estourou,
  para de reiniciar e **alerta** pedindo intervencao manual.
- Estado de cooldown/rate-limit fica em `STATE_DIR` (default `/var/lib/waha-watchdog`,
  provisionado pelo `StateDirectory=` do systemd).

## Pre-requisitos

```bash
sudo apt-get install -y curl jq    # geralmente ja presentes
```

> IMPORTANTE: o restart de sessao so e indolor (sem QR) se a **autenticacao do WAHA
> for persistente**. Garanta volume persistente para `/app/.sessions` (engine WEBJS)
> ou storage em Postgres (engine GOWS/NOWEB conforme config). Sem persistencia, um
> restart pode, sim, exigir novo QR — valide isso no seu deploy do WAHA.

## Instalacao (systemd timer — recomendado)

Os arquivos vivem aqui no repo em `deployment/waha-watchdog/`. Instalar:

```bash
# 1) Script
sudo install -D -m 0755 deployment/waha-watchdog/waha-watchdog.sh \
  /opt/waha-watchdog/waha-watchdog.sh

# 2) Config (NAO versionar o arquivo real — contem a API key)
sudo install -d -m 0750 /etc/waha-watchdog
sudo install -m 0640 deployment/waha-watchdog/waha-watchdog.env.example \
  /etc/waha-watchdog/waha-watchdog.env
sudo "${EDITOR:-nano}" /etc/waha-watchdog/waha-watchdog.env   # preencher URL/API key

# 3) Unit + timer
sudo install -m 0644 deployment/waha-watchdog/waha-watchdog.service \
  /etc/systemd/system/waha-watchdog.service
sudo install -m 0644 deployment/waha-watchdog/waha-watchdog.timer \
  /etc/systemd/system/waha-watchdog.timer

# 4) Ativar
sudo systemctl daemon-reload
sudo systemctl enable --now waha-watchdog.timer
```

Verificar:

```bash
systemctl list-timers waha-watchdog.timer        # proximo disparo
systemctl status waha-watchdog.service           # ultimo ciclo
journalctl -u waha-watchdog.service -f           # logs ao vivo
sudo systemctl start waha-watchdog.service       # forcar um ciclo agora
```

## Variaveis de ambiente

| Variavel | Default | Descricao |
|----------|---------|-----------|
| `WAHA_API_URL` | `http://localhost:3000` | URL base do WAHA. |
| `WAHA_API_KEY` | _(vazio)_ | API key (header `X-Api-Key`). Opcional se WAHA sem auth. |
| `SESSIONS` | _(vazio)_ | Sessoes a monitorar (espaco/virgula). Vazio = todas via API. |
| `HEALTHY_STATUSES` | `WORKING` | Status saudaveis (espaco/virgula). |
| `ALERT_ONLY` | `true` | `true` = so alerta; `false` = habilita restart. |
| `COOLDOWN_SECONDS` | `300` | Espera minima entre restarts da mesma sessao. |
| `MAX_RESTARTS_PER_WINDOW` | `3` | Maximo de restarts por sessao na janela. |
| `RESTART_WINDOW_SECONDS` | `3600` | Tamanho da janela do rate-limit. |
| `PING_RETRIES` | `5` | Tentativas de `/ping` antes de desistir do ciclo. |
| `PING_RETRY_DELAY` | `5` | Backoff base (s) entre tentativas de `/ping` (dobra). |
| `CURL_TIMEOUT` | `10` | Timeout por request curl (s). |
| `ALERT_WEBHOOK` | _(vazio)_ | URL p/ POST JSON de alertas (Slack/Discord/n8n). |
| `STATE_DIR` | `/var/lib/waha-watchdog` | Dir de estado (systemd seta via `StateDirectory`). |
| `INBOUND_GAP_MONITOR` | `false` | `true` = mede gap de inbound (SO-ALERTA). |
| `INBOUND_GAP_THRESHOLD` | `1800` | Segundos sem inbound novo p/ alertar. |

## Ligar o auto-restart depois do periodo ALERT_ONLY

O default e **observar primeiro**. Procedimento recomendado:

1. **Observar (dias 1-N, `ALERT_ONLY=true`):** deixe o timer rodando e acompanhe
   `journalctl -u waha-watchdog.service`. Confirme que:
   - sessoes saudaveis aparecem como `OK (status=WORKING)`;
   - quedas reais aparecem como `ALERT_ONLY: sessao precisaria de restart ...`;
   - **nao ha falso-positivo** (ex: `STARTING` transitorio sendo flagado — se for
     comum no seu deploy, adicione `STARTING` a `HEALTHY_STATUSES` ou aumente o
     intervalo do timer).
2. **Validar o cooldown/rate-limit:** garanta que os defaults
   (`COOLDOWN_SECONDS`, `MAX_RESTARTS_PER_WINDOW`, `RESTART_WINDOW_SECONDS`)
   fazem sentido para o seu volume.
3. **Confirmar persistencia de auth do WAHA:** faca um restart MANUAL de uma sessao
   (`curl -X POST -H "X-Api-Key: ..." $WAHA_API_URL/api/sessions/<nome>/restart`)
   e confirme que **volta para `WORKING` sem pedir QR**. Esse e o teste decisivo.
4. **Habilitar:** edite a config e recarregue (timer pega no proximo ciclo; nao
   precisa restart de servico do WAHA nem do Chatwoot):
   ```bash
   sudo sed -i 's/^ALERT_ONLY=.*/ALERT_ONLY=false/' /etc/waha-watchdog/waha-watchdog.env
   sudo systemctl start waha-watchdog.service   # opcional: dispara um ciclo ja com restart ativo
   ```
5. **Rollback instantaneo:** se algo sair errado, volte para alerta:
   ```bash
   sudo sed -i 's/^ALERT_ONLY=.*/ALERT_ONLY=true/' /etc/waha-watchdog/waha-watchdog.env
   ```

## Alternativa: cron (em vez de systemd timer)

```cron
# /etc/cron.d/waha-watchdog  — a cada 1 min
* * * * * root . /etc/waha-watchdog/waha-watchdog.env; STATE_DIR=/var/lib/waha-watchdog /opt/waha-watchdog/waha-watchdog.sh >> /var/log/waha-watchdog.log 2>&1
```

Crie o `STATE_DIR` antes (`sudo install -d -m 0755 /var/lib/waha-watchdog`). O
script ja serializa por ciclo; com cron de 1 min, mantenha `CURL_TIMEOUT` baixo
para evitar sobreposicao de execucoes.

## Teste manual (dry-run seguro)

Como `ALERT_ONLY=true` e default, da para rodar a mao sem risco:

```bash
WAHA_API_URL=https://waha.simplexsolucoes.com.br \
WAHA_API_KEY=... \
STATE_DIR=/tmp/waha-wd-test \
deployment/waha-watchdog/waha-watchdog.sh
```

Deve listar cada sessao com `OK (status=WORKING)` ou, em queda, logar
`ALERT_ONLY: sessao precisaria de restart`. Nenhuma chamada de restart e feita
enquanto `ALERT_ONLY=true`.
