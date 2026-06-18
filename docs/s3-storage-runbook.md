# Runbook — Migrar storage de anexos para S3 / compatível (R2 / Spaces / MinIO)

> **Por quê:** com `DIRECT_UPLOADS_ENABLED=true`, o browser pode dar `PUT` **direto no
> bucket** (presigned URL) em vez de passar os bytes pelo Puma + disco local. É a
> alavanca real de velocidade para arquivos grandes (e tira o servidor do caminho).
>
> **Status:** pronto para executar — **bloqueado apenas nas credenciais**. Os serviços
> já existem em `config/storage.yml` (`amazon` e `s3_compatible`) e
> `config/environments/production.rb` já lê `ACTIVE_STORAGE_SERVICE`.
>
> **Cutover SEM migração:** `active_storage_blobs.service_name` existe → os anexos
> antigos (`service_name = local`) continuam sendo servidos do **disco local**; só os
> **novos** vão para o bucket. Reversível trocando uma env var.

---

## 1. Preencher o `.env` do staging (não commitar segredo)

### AWS S3
```env
ACTIVE_STORAGE_SERVICE=amazon
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=us-east-1
S3_BUCKET_NAME=meu-bucket
```

### Cloudflare R2 / DigitalOcean Spaces / MinIO (S3-compatível)
```env
ACTIVE_STORAGE_SERVICE=s3_compatible
STORAGE_ACCESS_KEY_ID=...
STORAGE_SECRET_ACCESS_KEY=...
STORAGE_REGION=auto            # R2: "auto"; Spaces: ex. "nyc3"
STORAGE_BUCKET_NAME=meu-bucket
STORAGE_ENDPOINT=https://<conta>.r2.cloudflarestorage.com   # endpoint do provedor
STORAGE_FORCE_PATH_STYLE=true  # MinIO/alguns compatíveis; AWS/R2 normalmente false
```

## 2. CORS do bucket (obrigatório p/ DirectUpload do browser)

O `PUT` direto vem do navegador na origem do dashboard → o bucket precisa liberar CORS.
Aplique no painel do provedor (ou via CLI se sua key tiver permissão):

```json
[
  {
    "AllowedOrigins": ["https://nicolas.chatspx.app"],
    "AllowedMethods": ["PUT", "GET", "HEAD"],
    "AllowedHeaders": ["Content-Type", "Content-MD5", "Content-Disposition", "x-amz-*"],
    "ExposeHeaders": ["ETag", "Origin"],
    "MaxAgeSeconds": 3600
  }
]
```
(em produção, trocar a origem pela do domínio real de cada conta/host).

## 3. Cutover (sem downtime, sem migração)

1. Preencher `.env` (passo 1) + CORS (passo 2).
2. `sudo /bin/systemctl restart chatwoot.target` (recarrega a env).
3. A partir daí, **novos** anexos vão para o bucket (`service_name` do novo serviço);
   anexos **antigos** seguem em `service_name=local` e continuam abrindo do disco.

> Não é preciso migrar `/storage`. Se um dia quiser consolidar, dá para reupload via
> rake/`ActiveStorage::Blob`, mas **não é necessário** para a feature funcionar.

## 4. Validação no staging (Playwright/manual)

- Anexar uma imagem/PDF numa conversa → confirmar no DevTools que o `PUT` vai para o
  **endpoint do bucket** (não para `/rails/active_storage/disk`).
- Enviar → a mensagem persiste e o anexo **novo** abre normalmente.
- Abrir um anexo **antigo** (pré-cutover) → continua abrindo (servido do disco local).
- Conferir no bucket que o objeto novo apareceu.

## 5. Rollback

- Reverter `ACTIVE_STORAGE_SERVICE` para `local` (ou remover a env) + restart.
- Anexos criados durante a janela S3 ficam com `service_name` do bucket; para abri-los
  após o rollback, o serviço S3 precisa continuar **definido** em `storage.yml` (está) e
  as credenciais válidas — então mantenha as chaves enquanto houver objetos no bucket.

## 6. Riscos / observações

- **CORS errado** → o `PUT` do browser falha (o app cai no fallback ou erro). Validar 1º.
- **`force_path_style`**: AWS/R2 = `false`; MinIO e alguns compatíveis = `true`.
- **Custos/egress**: downloads de mídia passam a sair do bucket (egress do provedor).
- **Não derruba** instalações sem DirectUpload: o cutover só muda o destino do blob;
  o caminho indirect (flag off) continua válido.
- **X-Accel-Redirect**: o download autenticado hoje usa `send_file_accel` (nginx) para o
  disco; com S3 o ActiveStorage redireciona para URL assinada do bucket — validar que o
  download de mídia continua ok no fluxo de download em massa (.zip).
