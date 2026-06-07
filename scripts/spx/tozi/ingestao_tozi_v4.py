# -*- coding: utf-8 -*-
"""Ingestao v4 — proprietarios de VENDA Tozi (lista nova de verdade).
Sanitiza, remove corretores (blacklist) + ja-enviados (DB disparo locacao) + dedup interno.
Canonical = DDD + ultimos 8 digitos. Saida: tozi_venda_limpa.csv.
"""
import pandas as pd
import csv
import re

NEW_XLSX = 'PROPRIETARIOS VENDA - removidos ativos, removidos duplicatas, removidos proprietários locação.xlsx'
BLACKLIST = 'TODOS CORRETORES DE SINOP.csv'
SENT = 'sent_phones.txt'
OUT = 'tozi_venda_limpa.csv'
REVIEW = 'tozi_venda_revisao.csv'

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


def strip_ddi(d):
    if d.startswith('55') and len(d) >= 12:
        return d[2:]
    return d


def canonical(raw):
    d = strip_ddi(digits(raw))
    if not (10 <= len(d) <= 11):
        return None
    if d[:2] not in DDD_VALIDOS:   # rejeita DDD invalido (02, 05, etc.)
        return None
    return d[:2] + d[-8:]


def to_e164(raw):
    d = strip_ddi(digits(raw))
    if not (10 <= len(d) <= 11):
        return None
    if d[:2] not in DDD_VALIDOS:
        return None
    return '+55' + d


broker = set()
with open(BLACKLIST, encoding='utf-8', errors='replace') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        c = canonical(re.split(r'[;,]', line)[-1])
        if c:
            broker.add(c)

sent = set()
with open(SENT, encoding='utf-8', errors='replace') as f:
    for line in f:
        c = canonical(line.strip())
        if c:
            sent.add(c)

df = pd.read_excel(NEW_XLSX, dtype=str)
name_col = 'NOME' if 'NOME' in df.columns else df.columns[0]
phone_col = 'TELEFONE' if 'TELEFONE' in df.columns else df.columns[1]

clean, review, seen = [], [], set()
stats = dict(total=0, sem_canonical=0, corretor=0, ja_enviado=0, dup_interno=0, net_new=0)

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

print('blacklist corretores:', len(broker), '| ja-enviados:', len(sent))
print('STATS:', stats)
print('NET-NEW a enviar:', len(clean), '->', OUT)
print('revisao manual:', len(review), '->', REVIEW)
# distribuicao por DDD dos net-new (sanity)
from collections import Counter
ddd = Counter(c[2][:2] for c in clean)
print('top DDDs net-new:', ddd.most_common(8))
print('--- amostra ---')
for row in clean[:6]:
    print('  ', row)
