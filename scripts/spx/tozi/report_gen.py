# -*- coding: utf-8 -*-
"""Gera o Relatorio de Disparos Tozi (HTML -> PDF via Edge headless)."""
import json
import subprocess
import os
from datetime import datetime

USD_BRL = 5.01

with open('report_data.json', encoding='utf-8') as f:
    D = json.load(f)

c1 = D['campaigns']['1']
c2 = D['campaigns']['2']
cost = D['cost']


def i(n):  # inteiro com milhar BR: 1529 -> 1.529
    return f'{int(round(n)):,}'.replace(',', '.')


def d(n):  # decimal BR: 1065.5 -> 1.065,50
    return f'{n:,.2f}'.replace(',', '_').replace('.', ',').replace('_', '.')


def pct(n):  # 24.5 -> 24,5
    return f'{n:.1f}'.replace('.', ',')


def reached(c):
    return c['status'].get('delivered', 0) + c['status'].get('read', 0)


def fail_total(c):
    return c['status'].get('failed', 0)


def pos_buttons(c):
    b = c['buttons']
    return (b.get('Sim, pode falar', 0) + b.get('Tenho interesse', 0)
            + b.get('Quero saber mais', 0) + b.get('Quero saber', 0))


def resched_buttons(c):
    b = c['buttons']
    return (b.get('Agendar horário', 0) + b.get('Quero, mas outro horário', 0)
            + b.get('Me chama depois', 0))


TMPL_LABELS = {
    'tozi_venda_abertura': 'Curto — "Tá podendo falar?"',
    'tozi_venda_prioridade': 'Longo — prioridade',
    'tozi_venda_investidor': 'Longo — investidor',
    'tozi_venda_condicoes': 'Longo — condições',
    'tozi_venda_condicao': 'Refinado — condição',
    'tozi_venda_invest': 'Refinado — investimento',
    'tozi_venda_suites': 'Refinado — 3 suítes',
    'tozi_venda_oportunidade': 'Qualificado — oportunidade',
    'tozi_venda_lembrei': 'Qualificado — lembrei',
}


def template_perf_block(c):
    st = c['by_template']
    rep = c.get('replied_by_template', {})
    rows = []
    for t, n in st.items():
        if not t or n < 1:
            continue
        r = rep.get(t, 0)
        rows.append((100.0 * r / n if n else 0, t, n, r))
    rows.sort(reverse=True)
    rmax = max((x[0] for x in rows), default=1) or 1
    body = ''
    for rate, t, n, r in rows:
        small = ' <span class="sm">(amostra pequena)</span>' if n < 50 else ''
        w = max(3, round(100 * rate / rmax))
        body += (f'<tr><td>{TMPL_LABELS.get(t, t)}{small}</td>'
                 f'<td class="num">{i(n)}</td><td class="num">{i(r)}</td>'
                 f'<td class="rate"><div class="bar" style="width:{w}%"></div><span>{pct(rate)}%</span></td></tr>')
    return body


def reply_rate(c):
    return 100.0 * c['replied'] / c['total'] if c['total'] else 0


def fail_label(code):
    return {'131026': 'sem WhatsApp', '131049': 'limite Meta (pacing)',
            '130472': 'limite Meta (pacing)', '132000': 'erro de parâmetro'}.get(code, code)


def fail_rows(c):
    agg = {}
    for code, n in c['fail_codes'].items():
        lbl = fail_label(code)
        agg[lbl] = agg.get(lbl, 0) + n
    return agg


def broker_rows(c):
    return {k: v for k, v in sorted(c['by_broker'].items(), key=lambda x: -x[1]) if not k.startswith('#')}


tot_contact = c1['total'] + c2['total']
tot_reach = reached(c1) + reached(c2)
tot_reply = c1['replied'] + c2['replied']
brl = cost['marketing_usd'] * USD_BRL
brl_iof = brl * 1.035
hoje = datetime.now().strftime('%d/%m/%Y %H:%M')


def campaign_block(c, badge, badge_class):
    fr = fail_rows(c)
    br = broker_rows(c)
    fail_html = ' · '.join(f'{lbl}: <b>{i(n)}</b>' for lbl, n in fr.items())
    broker_html = ''.join(f'<tr><td>{k}</td><td class="num">{i(v)}</td></tr>' for k, v in br.items())
    return f'''
    <div class="card">
      <div class="card-head"><h2>{c['label']}</h2><span class="badge {badge_class}">{badge}</span></div>
      <div class="kpis">
        <div class="kpi"><span class="kn">{i(c['total'])}</span><span class="kl">enviados</span></div>
        <div class="kpi"><span class="kn">{i(reached(c))}</span><span class="kl">entregues + lidos</span></div>
        <div class="kpi good"><span class="kn">{i(c['replied'])}</span><span class="kl">respostas ({pct(reply_rate(c))}%)</span></div>
        <div class="kpi bad"><span class="kn">{i(fail_total(c))}</span><span class="kl">falhas</span></div>
      </div>
      <div class="detail">
        <div class="dcol"><h3>Respostas</h3>
          <p>👍 Interesse positivo: <b>{i(pos_buttons(c))}</b><br>
             🕐 Pediram outro horário: <b>{i(resched_buttons(c))}</b><br>
             💬 Total que respondeu: <b>{i(c['replied'])}</b></p></div>
        <div class="dcol"><h3>Falhas (não cobradas)</h3><p>{fail_html}</p></div>
        <div class="dcol"><h3>Por corretor</h3><table class="mini">{broker_html}</table></div>
      </div>
    </div>'''


html = f'''<!DOCTYPE html><html lang="pt-BR"><head><meta charset="utf-8">
<style>
  @page {{ size: A4; margin: 10mm 13mm; }}
  * {{ box-sizing: border-box; font-family: 'Segoe UI', Arial, sans-serif; }}
  body {{ color: #1a2233; margin: 0; }}
  .top {{ display:flex; justify-content:space-between; align-items:flex-end; border-bottom: 3px solid #00a050; padding-bottom: 10px; }}
  .top h1 {{ margin:0; font-size: 22px; color:#008040; }}
  .top .sub {{ color:#667; font-size: 12px; }}
  .top .when {{ text-align:right; font-size:11px; color:#889; }}
  .summary {{ display:flex; gap:10px; margin:12px 0; }}
  .scard {{ flex:1; background:#00a050; color:#fff; border-radius:10px; padding:14px; text-align:center; }}
  .scard.alt {{ background:#114433; }}
  .scard .n {{ font-size:25px; font-weight:700; display:block; }}
  .scard .l {{ font-size:11px; opacity:.9; }}
  .card {{ border:1px solid #dde; border-radius:10px; padding:12px 16px; margin-bottom:10px; }}
  .card-head {{ display:flex; justify-content:space-between; align-items:center; margin-bottom:10px; }}
  .card-head h2 {{ margin:0; font-size:16px; color:#114433; }}
  .badge {{ font-size:11px; font-weight:700; padding:3px 10px; border-radius:20px; color:#fff; }}
  .badge.done {{ background:#3377aa; }}
  .badge.paused {{ background:#ee9900; }}
  .kpis {{ display:flex; gap:10px; margin-bottom:12px; }}
  .kpi {{ flex:1; background:#f5f7fa; border-radius:8px; padding:10px; text-align:center; }}
  .kpi.good {{ background:#eafaf0; }}
  .kpi.bad {{ background:#fdeeee; }}
  .kpi .kn {{ font-size:20px; font-weight:700; display:block; color:#114433; }}
  .kpi .kl {{ font-size:10px; color:#667; }}
  .detail {{ display:flex; gap:16px; }}
  .dcol {{ flex:1; }}
  .dcol h3 {{ font-size:12px; margin:0 0 4px; color:#00a050; text-transform:uppercase; letter-spacing:.5px; }}
  .dcol p {{ font-size:12px; margin:0; line-height:1.6; }}
  table.mini {{ width:100%; font-size:12px; border-collapse:collapse; }}
  table.mini td {{ padding:2px 0; border-bottom:1px solid #eef; }}
  table.mini .num {{ text-align:right; font-weight:600; }}
  table.perf {{ width:100%; font-size:12px; border-collapse:collapse; }}
  table.perf th {{ text-align:left; font-size:10px; color:#889; text-transform:uppercase; padding:4px 6px; border-bottom:2px solid #dde; }}
  table.perf th.num, table.perf td.num {{ text-align:right; }}
  table.perf td {{ padding:5px 6px; border-bottom:1px solid #eef; }}
  table.perf .rate {{ position:relative; width:150px; }}
  table.perf .rate .bar {{ position:absolute; left:6px; top:5px; bottom:5px; background:#bfe9cf; border-radius:3px; z-index:0; }}
  table.perf .rate span {{ position:relative; z-index:1; font-weight:700; color:#114433; }}
  .sm {{ font-size:9px; color:#aab; font-weight:400; }}
  .cost {{ background:#f5f7fa; border-radius:10px; padding:12px 16px; margin-bottom:10px; }}
  .cost h2 {{ font-size:16px; margin:0 0 8px; color:#114433; }}
  .cost .big {{ font-size:24px; font-weight:700; color:#00a050; }}
  .insight {{ background:#eafaf0; border-left:4px solid #00a050; border-radius:6px; padding:12px 16px; font-size:12px; line-height:1.7; }}
  .foot {{ margin-top:14px; font-size:10px; color:#99a; text-align:center; }}
</style></head><body>
  <div class="top">
    <div><h1>Relatório de Disparos · WhatsApp</h1><div class="sub">Tozi Imóveis · Lançamento Aquarela das Artes</div></div>
    <div class="when">Atualizado em<br><b>{hoje}</b></div>
  </div>
  <div class="summary">
    <div class="scard"><span class="n">{i(tot_contact)}</span><span class="l">leads contatados</span></div>
    <div class="scard"><span class="n">{i(tot_reach)}</span><span class="l">entregues + lidos</span></div>
    <div class="scard"><span class="n">{i(tot_reply)}</span><span class="l">respostas</span></div>
    <div class="scard alt"><span class="n">R$ {i(brl_iof)}</span><span class="l">investido (Meta)</span></div>
  </div>
  {campaign_block(c1, 'CONCLUÍDO', 'done')}
  {campaign_block(c2, 'PAUSADO', 'paused')}
  <div class="card">
    <div class="card-head"><h2>🎯 Qual copy converte melhor — Venda</h2></div>
    <table class="perf">
      <tr><th>Template (abordagem)</th><th class="num">Enviados</th><th class="num">Respostas</th><th>Taxa de resposta</th></tr>
      {template_perf_block(c2)}
    </table>
  </div>
  <div class="cost">
    <h2>💰 Custo real (Meta · API oficial)</h2>
    <p style="font-size:13px;margin:0;">
      <span class="big">US$ {d(cost['marketing_usd'])}</span> &nbsp;≈&nbsp; <b>R$ {i(brl)}</b> (câmbio R$ {d(USD_BRL)}) · ~R$ {i(brl_iof)} com IOF<br>
      {i(cost['marketing_msgs'])} mensagens de marketing entregues × US$ 0,0625 cada.<br>
      {i(cost['service_msgs'])} mensagens de atendimento (respostas dentro de 24h) = <b>R$ 0 (grátis)</b>.<br>
      Falhas de entrega (sem WhatsApp / limite) <b>não são cobradas</b>.
    </p>
  </div>
  <div class="insight">
    <b>📈 Leitura dos números:</b><br>
    • O <b>template curto</b> ("Tá podendo falar?") domina em volume: <b>28,5% de resposta</b> (459 de 1.609) — mas boa parte é cliente respondendo por reflexo, nem toda qualificada.<br>
    • Os templates que <b>explicam a oferta</b> (longos e refinados) respondem menos — <b>6% a 11%</b> — porém tendem a trazer interesse mais real.<br>
    • O <b>A/B qualificado</b> (oportunidade × lembrei) foi <b>pausado cedo</b> (23+23 enviados) — amostra insuficiente pra cravar o vencedor.<br>
    • Custo por resposta: ~<b>R$ {d(brl_iof / tot_reply)}</b>. A base de venda já foi <b>esgotada</b> ({i(c2['total'])} contatados no total).
  </div>
  <div class="foot">Gerado a partir dos dados de produção (Chat SPX) e da API de faturamento da Meta · Simplex Soluções</div>
</body></html>'''

with open('relatorio_disparos_tozi.html', 'w', encoding='utf-8') as f:
    f.write(html)

edge = r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
out = os.path.abspath('Relatorio-Disparos-Tozi.pdf')
src = os.path.abspath('relatorio_disparos_tozi.html')
if os.path.exists(out):
    os.remove(out)
subprocess.run([edge, '--headless', '--disable-gpu', f'--print-to-pdf={out}',
                '--no-pdf-header-footer', f'file:///{src}'], timeout=60)
print('PDF:', out, '|', os.path.getsize(out) if os.path.exists(out) else 'FALHOU', 'bytes')
