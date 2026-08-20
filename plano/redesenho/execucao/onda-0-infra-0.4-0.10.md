# Onda 0 — blocos 0.4 e 0.10 (infra local)

**Medido em:** 17/08/2026 · VM `192.168.8.232` (homologação) · pelo coordenador
**Estado anterior:** os dois estavam declarados **FAIL, bloqueados por falta de `sudo`**, no
relatório `onda-0.md` de 13/08/2026 14:23.

Nenhum comando com privilégio foi executado e nenhuma senha foi pedida. Tudo abaixo é
medição somente-leitura. **Os dois blocos mudaram de estado desde aquele relatório** — a
configuração da VM foi alterada por alguém depois dele (o diretório `/etc/nginx` tem mtime
`13/08 19:03`, quatro horas e meia depois da medição que reprovou o bloco).

---

## 0.4 — compressão de `text/css` e `application/javascript`

**Aceite do PLANO-MESTRE §2.2:** *"`curl -skI -H "Accept-Encoding: gzip, br"` devolve
`content-encoding`"*.

### Medição (17/08/2026)

Assets descobertos no HTML real servido (`/app/login`), os dois vhosts desta VM:

| Vhost | Asset | HTTP | `content-type` | `content-encoding` |
|---|---|---:|---|---|
| `hmlchat.simplexsolucoes.com.br` | `v3app-BNzlNDUp.js` | 200 | `text/javascript` | **gzip** |
| `hmlchat.simplexsolucoes.com.br` | `v3app-B_LIh5O2.css` | 200 | `text/css` | **gzip** |
| `chatspx.app` | `v3app-BNzlNDUp.js` | 200 | `text/javascript` | **gzip** |
| `chatspx.app` | `v3app-B_LIh5O2.css` | 200 | `text/css` | **gzip** |

**Aceite local: PASS — 4/4 assets comprimidos.** Era 0/4 em 13/08.

Comando reproduzível:

```bash
HTML=$(curl -sk https://hmlchat.simplexsolucoes.com.br/app/login)
JS=$(echo "$HTML"  | grep -oE '/vite/assets/[a-zA-Z0-9._-]+\.js'  | head -1)
CSS=$(echo "$HTML" | grep -oE '/vite/assets/[a-zA-Z0-9._-]+\.css' | head -1)
for host in hmlchat.simplexsolucoes.com.br chatspx.app; do
  for a in $JS $CSS; do
    curl -skI -H "Accept-Encoding: gzip, br" "https://$host$a" \
      | grep -iE '^(HTTP|content-type|content-encoding)'
  done
done
```

### Por que tinha falhado, e por que a explicação importa

`nginx.conf:53` sempre teve `gzip_types` cobrindo `text/css`, `application/javascript` e
`text/javascript` — a lista **não** era o problema. O vhost
`sites-enabled/nginx_chatwoot.conf:48` serve **tudo** por `location / { proxy_pass
http://backend; }`, inclusive os assets do Vite: nesta instalação não há `location` que
sirva arquivo do disco. E o padrão do nginx é `gzip_proxied off`, que **desliga a compressão
para resposta vinda de upstream** — a linha `gzip_proxied any` está comentada em
`nginx.conf:49`.

Ou seja: a causa era resposta proxiada, não tipo MIME. Registrar isto tem valor porque a
correção óbvia (mexer em `gzip_types`) não teria efeito nenhum, e o bloco voltaria a
reprovar depois de uma mudança que parecia certa.

### O que continua aberto (e exige privilégio que esta sessão não tem)

1. **Brotli não existe nesta VM.** `ls /usr/lib/nginx/modules/ | grep brotli` → vazio;
   `nginx/1.24.0 (Ubuntu)` sem o módulo. O aceite literal do plano fala em *devolver
   `content-encoding`*, e **gzip o satisfaz**. Brotli seria ganho adicional (~15–20% sobre
   gzip em JS/CSS), não requisito. Para habilitar:
   `sudo apt install libnginx-mod-brotli` + `brotli on; brotli_types …;` + `sudo nginx -t` +
   `sudo systemctl reload nginx`. **Não executado.**
2. **As outras VMs da frota não foram medidas.** O texto do bloco 0.4 diz "nas 4 VMs, não só
   homologação". A correção de escopo do usuário limitou esta execução a esta VM, então as
   demais permanecem **não verificadas** — não reprovadas. O comando acima roda igual em
   cada uma, sem privilégio, e responde em segundos.
3. **`gzip_vary on` continua comentado** (`nginx.conf:48`). Sem ele, um cache intermediário
   pode servir a versão comprimida a um cliente que não a aceita. Risco baixo com CDN
   ausente, mas é uma linha e é a correção certa. Exige `sudo` para editar e recarregar.

---

## 0.10 — Active Record Encryption

**Aceite do PLANO-MESTRE §2.2:** *"`Chatwoot.encryption_configured?` → `true` em todas;
segredo novo grava cifrado; antigos continuam legíveis"*.

### Medição (17/08/2026), nesta VM

| Verificação | 13/08 | 17/08 |
|---|---|---|
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | ausente | **presente** |
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | ausente | **presente** |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | ausente | **presente** |
| `Chatwoot.encryption_configured?` | `false` | **`true`** |
| migrations pendentes | 0 | **0** |

Nenhum valor de chave foi lido, impresso ou copiado — só a presença da variável.

**Segredo novo grava cifrado — provado sem escrever nenhuma linha no banco.** Round-trip em
memória pelo próprio encryptor do Rails, com as chaves reais do ambiente:

```
cifra gerada?     true      (o texto cifrado difere do claro)
formato envelope? true      (sai no envelope JSON do Rails, que é o que a coluna guarda)
round-trip ok?    true      (decifra de volta exatamente o valor original)
```

**Estado dos dados já gravados:**

| Tabela.coluna | não-vazios | cifrados | texto puro |
|---|---:|---:|---:|
| `integrations_hooks.access_token` | 1 | **1** | **0** |
| `webhooks.secret` | 0 | 0 | 0 |
| `account_integrations.settings` | 2 | 0 | **2** |

O único `access_token` em texto puro que o relatório de 13/08 encontrou **já está cifrado**.
Os 2 registros de `account_integrations.settings` em texto puro foram gravados **antes** de
as chaves existirem; continuam legíveis por `support_unencrypted_data`, que é exatamente o
que o aceite pede ("antigos continuam legíveis"). Eles se cifram sozinhos no próximo save
do registro.

**Aceite local: PASS** nos três itens — configurado, grava cifrado, antigos legíveis.

### O que continua aberto

1. **A frota.** O aceite diz "em todas". Só esta VM foi medida; as outras permanecem **não
   verificadas**. A verificação por VM não precisa de `sudo`, precisa de acesso ao host:
   `bin/rails runner 'puts Chatwoot.encryption_configured?'`.
2. **Provisionar as chaves onde faltarem** exige escrever no `.env` de cada VM e reiniciar o
   serviço — as duas coisas fora do que esta sessão faz. Procedimento, para quem tiver o
   acesso: `bin/rails db:encryption:init` gera as três chaves; elas entram no `.env`; e o
   restart é `sudo systemctl restart chatwoot.target`.
   **Chave nova em VM que já tem dado cifrado torna esse dado ilegível** — por isso o passo 1
   (inventariar antes) não é burocracia.
3. **Determinístico não foi provado isoladamente.** O round-trip acima cobre a chave primária
   e o salt. A checagem do provider determinístico falhou por erro meu de API no script, não
   por configuração: a variável está presente e `user.otp_secret` (que é
   `deterministic: true`) é usado pelo app em produção nesta VM. Fica registrado como
   **não provado nesta medição**, não como falha.

---

## Resumo

| Bloco | 13/08 | 17/08 nesta VM | Continua aberto |
|---|---|---|---|
| **0.4** | FAIL 0/4 | **PASS 4/4** | brotli (precisa `sudo`+apt) · `gzip_vary` · as outras VMs |
| **0.10** | FAIL, `encryption_configured? = false` | **PASS** nos 3 itens | inventário e provisionamento nas outras VMs |

Nenhum dos dois bloqueia o restante da Onda 0.
</content>
