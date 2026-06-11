# Scripts de operação — Disparos Tozi (SPX)

Ferramentas usadas nas campanhas de disparo em massa HSM da Tozi (Account 6, inbox 91, AWS).
Rodam via `rails runner` (Ruby, na AWS) ou `python` (local, ingestão/relatório).
São operacionais (têm paths/IDs hardcoded) — arquivados aqui pra histórico e reuso.

## Ingestão (Python, local — sanitiza + dedup)
- `ingestao_tozi_v4.py` — proprietários de VENDA. Dedup: blacklist corretores + já-enviados (DB) + fake.
- `ingestao_inquilinos.py` — INQUILINOS. Dedup 4 camadas: + **conversa aberta** na inbox 91. Recupera 9-díg→DDD 66, 8-díg→66+9, trunk-0.

## Criação de templates (Ruby — Graph API)
- `create_venda_templates.rb` / `create_venda2_templates.rb` — templates de venda (texto, {{1}}=nome {{2}}=corretor).
- `create_abertura_template.rb` — curto "Tá podendo falar?".
- `create_qualif_templates.rb` — A/B qualificado (oportunidade vs lembrei).
- `create_inq_templates.rb` — **com IMAGEM** (resumable upload `/APP_ID/uploads` → handle → header IMAGE). Corpo sem variável.
- `create_followup_template.rb` — follow-up 1 variável ({{1}}=nome).

## Motores de disparo (Ruby — `rails runner`, `DRY=1` simula)
- `disparo_venda.rb` / `disparo_venda2.rb` / `disparo_venda_curto.rb` / `disparo_curto_lote2.rb` — venda (vários lotes/templates/corretores).
- `disparo_inq.rb` — inquilinos (3 templates, 2 com imagem).
- `disparo_ab.rb` — A/B (split 50/50 por lead).
- `followup_schedule.rb` — follow-up campanha 1 (re-engajamento, na conversa existente via `FollowupHsmJob`).
- `followup_venda_schedule.rb` — follow-up campanha 2 (venda).

## Relatório (Python — HTML→PDF via Edge headless)
- `report_data.rb` — coleta dados de produção + custo real (Meta `pricing_analytics`) → JSON.
- `report_gen.py` — gera o PDF (`Relatorio-Disparos-Tozi.pdf`).

## Jobs (no app, versionados): `app/jobs/spx/tozi/`
- `disparo_lead_job.rb` — cria conversa + envia HSM (corpo 2 var, corpo 0 var + header imagem).
- `followup_hsm_job.rb` — envia HSM na conversa EXISTENTE (re-engajamento, mantém corretor).

## Pausar um disparo
Deletar os jobs do `Sidekiq::ScheduledSet` (`DisparoLeadJob` ou `FollowupHsmJob`).
