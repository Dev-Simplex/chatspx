# Onda 0 — blocos 0.4 e 0.10: EXECUTADOS (24/08/2026)

Continuação de `onda-0-infra-0.4-0.10.md`, que era **medição somente-leitura** e deixava os dois
blocos com itens abertos "por falta de `sudo`". O acesso privilegiado foi concedido em 24/08 e os
itens foram executados.

---

## 0.4 — compressão

### Estado final nesta VM

| algoritmo | `hmlchat` | `chatspx.app` (origem) |
|---|---|---|
| gzip | ✅ | ✅ |
| **brotli** | ✅ **novo** | ✅ **novo** |
| `Vary: Accept-Encoding` | ✅ **novo** | ✅ **novo** |

Aceite do PLANO-MESTRE §2.2 (`curl -skI -H "Accept-Encoding: gzip, br"` devolve
`content-encoding`): **PASS**, agora em 6/6 combinações medidas por vhost.

### O que foi feito

1. `apt-get install libnginx-mod-http-brotli-filter libnginx-mod-http-brotli-static`
   (o pacote se chama `libnginx-mod-http-brotli-*`, não `libnginx-mod-brotli` como o documento
   anterior supunha).
2. `nginx.conf`: `gzip_vary on` e `gzip_proxied any` descomentados, `brotli on` +
   `brotli_comp_level 5` + `brotli_types` acrescentados. Backup em
   `/etc/nginx/nginx.conf.bak-spx-20260824-170633`.
3. `nginx -t` verde → `systemctl reload nginx`.

### Correção ao documento anterior

Ele registrou *"risco baixo com CDN ausente"* ao justificar a prioridade do `gzip_vary`.
**A CDN não está ausente:** `chatspx.app` resolve para IPs do Cloudflare e responde com
`server: cloudflare` / `cf-cache-status: HIT`. `hmlchat` vai direto à origem
(`177.65.155.246`). Os dois vhosts servem do MESMO nginx — confirmado forçando o `Host` contra
o IP de origem, onde os dois devolvem gzip, br e `Vary` idênticos. A diferença que aparece na
borda (`chatspx.app` sem `Vary`, preferindo gzip) é negociação do próprio Cloudflare.

Ou seja: `gzip_vary` era **mais** importante do que o documento supunha, não menos.

---

## 0.10 — Active Record Encryption

### Inventário da frota — o aceite estava REPROVADO fora da homologação

O aceite diz *"`Chatwoot.encryption_configured?` → `true` em todas"*. Medido em 24/08:

| VM | antes | tokens de integração | cifrados | **texto puro** | Telegram |
|---|---|---:|---:|---:|---:|
| HOMOLOG `.232` | `true` | 1 | 1 | 0 | 0 |
| PRODUCAO `.229` | **`false`** | 3 | 0 | **3** | 1 |
| TOZI | **`false`** | 5 | 0 | **5** | 0 |
| FABRICA | **`false`** | 1 | 0 | **1** | 0 |
| CATATAU | **`false`** | 0 | 0 | 0 | 0 |
| SENTINELA | **`false`** | 0 | 0 | 0 | 0 |
| ALTERNATIVO `.169` | — | — | — | — | — |
| PAULAO `.100` | — | — | — | — | — |

ALTERNATIVO e PAULAO estavam **sem rota** (porta 22 inacessível) — não verificadas, não
reprovadas.

**Nove tokens de integração estavam em texto puro no banco** de três VMs, incluindo produção.

### O que foi feito

Chaves provisionadas nas 5 VMs alcançáveis, **uma trinca própria por VM** (bancos independentes),
via `openssl rand -hex 32`. Script idempotente, com backup do `.env` e guarda contra estado
parcial. Valores nunca impressos.

O passo que o documento anterior exigia — *"inventariar ANTES, porque chave nova em VM que já tem
dado cifrado torna esse dado ilegível"* — foi cumprido: **0 linhas cifradas na frota inteira**,
então não havia nada que pudesse ficar ilegível.

### Verificado depois de provisionar

| VM | `configured?` | tokens antigos lidos | erros |
|---|---|---|---|
| PRODUCAO | `true` | 3/3 | 0 |
| TOZI | `true` | 5/5 | 0 |
| FABRICA | `true` | 1/1 | 0 |
| CATATAU | `true` | 0/0 | 0 |
| SENTINELA | `true` | 0/0 | 0 |

O dado antigo em claro segue legível por `support_unencrypted_data = true`
(`config/application.rb:110`) e se cifra sozinho no próximo save.

### A checagem que faltava fazer antes de reiniciar

Depois do restart, `encrypts :bot_token, deterministic: true if Chatwoot.encryption_configured?`
passa a valer — e `Webhooks::TelegramEventsJob` busca o canal por
`Channel::Telegram.find_by(bot_token: params[:bot_token])`, contra um valor **gravado em claro**.
Se essa busca falhasse, toda mensagem de Telegram seria descartada em silêncio.

Testada em processo novo na PRODUCAO (que já carrega as chaves, ou seja, já é o comportamento
pós-restart): **acha o canal**. A query sai com **2 candidatos** no `IN`, um deles o valor em
claro — é o `support_unencrypted_data` cobrindo a leitura E a busca.

### Estado

- **HOMOLOGAÇÃO: reiniciada** em 24/08 17:34. Aceite PASS no processo vivo.
- **Frota: provisionada, NÃO reiniciada.** As chaves ficam inertes até o próximo restart, o que
  mantém a operação reversível (basta remover as 3 linhas do `.env`; há backup em cada VM).
  Enquanto não reiniciar, o processo vivo segue com `configured? = false`.
- **ALTERNATIVO e PAULAO: pendentes**, sem rota.

---

## Defeito encontrado de passagem: `deterministic: true` do `otp_secret` não vale

`User#otp_secret` é declarado duas vezes:

- `devise-two-factor 6.1.0`, em `two_factor_authenticatable.rb:10` — `encrypts :otp_secret`
  (não determinístico), disparado pelo `devise :two_factor_authenticatable` (user.rb:67);
- nosso `app/models/user.rb:83` — `encrypts :otp_secret, deterministic: true`.

A nossa vem **depois** e `type_for_attribute(:otp_secret).scheme.deterministic?` responde `true`
— mas o efeito real é misto: usa a **chave** determinística com **IV aleatório**, então a mesma
entrada cifra diferente a cada chamada. Medido: `User.where(otp_secret: v).to_sql` duas vezes
seguidas devolve SQL diferente. Os outros dois atributos determinísticos
(`Channel::Telegram#bot_token`, `Integrations::Hook#access_token`) são estáveis — só o
`otp_secret` diverge.

**Impacto hoje: nenhum.** Ninguém busca por valor de `otp_secret` (só `where.not(..., nil)`, que é
teste de NULL), e há 0 usuários com `otp_secret` gravado nesta VM.

**Impacto latente:** o índice `index_users_on_otp_secret UNIQUE` (schema) não consegue detectar
duplicata, e qualquer `find_by(otp_secret:)` futuro devolveria `nil` calado.

Não corrigido: mexer na criptografia do MFA é decisão do dono, e as duas saídas possíveis
(remover a nossa linha 83, que é o que já acontece na prática; ou configurar
`splattable_encrypted_attr_options` do devise) têm consequência de segurança.
