# -*- coding: utf-8 -*-
# Enumera os bairros OFICIAIS de Sinop/MT varrendo as faixas de CEP via ViaCEP.
# Fonte autoritativa (Correios), gratuita, deterministica. Roda local (internet publica).
#
# Uso:
#   python scripts/spx/tozi/viacep_bairros.py [step]   (step default 12; menor = mais fino)
# Saida: Temp/viacep_bairros_sinop.json  (bairro, hits ~ tamanho, cep_exemplo)

import json, sys, urllib.request
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor

START, END = 78550000, 78559999          # faixa observada de Sinop (78550..78557) + folga
STEP = int(sys.argv[1]) if len(sys.argv) > 1 else 12
UA = {'User-Agent': 'chatspx-gazetteer/1.0 (uso interno; conciliacao de bairros)'}

def fetch(cep):
    url = f'https://viacep.com.br/ws/{cep:08d}/json/'
    for _ in range(2):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=12) as r:
                d = json.load(r)
            if d.get('erro'):
                return None
            if (d.get('localidade') or '').strip().lower() != 'sinop':
                return None
            if (d.get('uf') or '').upper() != 'MT':
                return None
            return d
        except Exception:
            continue
    return None

ceps = list(range(START, END + 1, STEP))
print(f'amostrando {len(ceps)} CEPs (step {STEP})...', file=sys.stderr)
res = []
with ThreadPoolExecutor(max_workers=6) as ex:
    for i, d in enumerate(ex.map(fetch, ceps)):
        if d:
            res.append(d)
        if i % 100 == 0:
            print(f'  {i}/{len(ceps)} — validos ate agora: {len(res)}', file=sys.stderr)

bairros = defaultdict(lambda: {'hits': 0, 'ceps': set()})
for d in res:
    b = (d.get('bairro') or '').strip() or '(CEP geral / sem bairro)'
    bairros[b]['hits'] += 1
    bairros[b]['ceps'].add(d.get('cep'))

out = [{'bairro': b, 'hits': v['hits'], 'cep_exemplo': sorted(v['ceps'])[0]}
       for b, v in sorted(bairros.items(), key=lambda kv: -kv[1]['hits'])]
json.dump(out, open('Temp/viacep_bairros_sinop.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)

print(f'\nSinop: {len(res)} CEPs validos amostrados -> {len(out)} bairros distintos')
for o in out:
    print(f"  {o['hits']:4d}  {o['bairro']}  (ex {o['cep_exemplo']})")
