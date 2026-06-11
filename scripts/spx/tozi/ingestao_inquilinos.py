# -*- coding: utf-8 -*-
"""Ingestao INQUILINOS Tozi — sanitiza + dedup 4 camadas.
Exclui: corretores (blacklist) + ja-enviados (disparo) + CONVERSA ABERTA (inbox 91) + dup interno.
Canonical = DDD + ultimos 8 digitos (DDD valido). Saida: tozi_inquilinos_limpa.csv.
"""
import pandas as pd
import csv
import re

NEW_XLSX = 'INQUILINOS.xlsx'
BLACKLIST = 'TODOS CORRETORES DE SINOP.csv'
SENT = 'sent_phones.txt'
OPEN = 'open_phones.txt'
OUT = 'tozi_inquilinos_limpa.csv'
REVIEW = 'tozi_inq_revisao_v2.csv'

DDD_VALIDOS = {str(d) for d in [
    11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 24, 27, 28, 31, 32, 33, 34, 35, 37, 38,
    41, 42, 43, 44, 45, 46, 47, 48, 49, 51, 53, 54, 55, 61, 62, 63, 64, 65, 66, 67, 68,
    69, 71, 73, 74, 75, 77, 79, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92, 93, 94, 95,
    96, 97, 98, 99]}


def digits(s):
    s = str(s or '').strip()
    if s.endswith('.0'):
        s = s[:-2]
    return re.sub(r'\D', '', s)


def norm_local(raw):
    """Numero local (DDD+assinante, sem +55) ja recuperado, ou None.
    Recupera: trunk-0 (tira o 0, mantem DDD), 9-dig sem DDD (assume 66),
    8-dig (assume DDD 66 + 9)."""
    d = digits(raw)
    if not d:
        return None
    if d.startswith('0') and len(d) in (11, 12):   # trunk-0
        d = d[1:]
    if d.startswith('55') and len(d) >= 12:         # DDI
        d = d[2:]
    if len(d) == 9:                                  # celular sem DDD -> assume 66
        d = '66' + d
    elif len(d) == 8:                                # 8 digitos -> DDD 66 + 9
        d = '66' + '9' + d
    if not (10 <= len(d) <= 11) or d[:2] not in DDD_VALIDOS:
        return None
    return d


def canonical(raw):
    d = norm_local(raw)
    return d[:2] + d[-8:] if d else None


def to_e164(raw):
    d = norm_local(raw)
    return '+55' + d if d else None


def load_canon(path):
    s = set()
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            for line in f:
                c = canonical(line.strip())
                if c:
                    s.add(c)
    except FileNotFoundError:
        pass
    return s


broker = set()
with open(BLACKLIST, encoding='utf-8', errors='replace') as f:
    for line in f:
        line = line.strip()
        if line:
            c = canonical(re.split(r'[;,]', line)[-1])
            if c:
                broker.add(c)

sent = load_canon(SENT)
openc = load_canon(OPEN)

df = pd.read_excel(NEW_XLSX, dtype=str)
name_col = 'NOME' if 'NOME' in df.columns else df.columns[0]
phone_col = 'TELEFONE' if 'TELEFONE' in df.columns else df.columns[1]

clean, review, seen = [], [], set()
stats = dict(total=0, sem_canonical=0, corretor=0, ja_enviado=0, conversa_aberta=0, dup_interno=0, net_new=0)

for _, r in df.iterrows():
    stats['total'] += 1
    name = (str(r[name_col]).strip() if r[name_col] is not None else '')
    phone = r[phone_col]
    c = canonical(phone)
    if not c:
        stats['sem_canonical'] += 1
        review.append((name, str(phone), 'sem_canonical_ou_ddd_invalido'))
        continue
    if c in broker:
        stats['corretor'] += 1
        continue
    if c in sent:
        stats['ja_enviado'] += 1
        continue
    if c in openc:
        stats['conversa_aberta'] += 1
        continue
    if c in seen:
        stats['dup_interno'] += 1
        continue
    seen.add(c)
    clean.append((name, to_e164(phone), c))
    stats['net_new'] += 1

with open(OUT, 'w', encoding='utf-8', newline='') as f:
    w = csv.writer(f)
    w.writerow(['nome', 'telefone_e164', 'canonical'])
    w.writerows(clean)

with open(REVIEW, 'w', encoding='utf-8', newline='') as f:
    w = csv.writer(f)
    w.writerow(['nome', 'telefone_raw', 'motivo'])
    w.writerows(review)

print('blacklist corretores:', len(broker), '| ja-enviados:', len(sent), '| conversas abertas:', len(openc))
print('STATS:', stats)
print('NET-NEW a enviar:', len(clean), '->', OUT)
from collections import Counter
ddd = Counter(c[2][:2] for c in clean)
print('top DDDs net-new:', ddd.most_common(6))
for row in clean[:5]:
    print('  ', row)
