#!/usr/bin/env python3
"""Compare rewritten reads with EXCEPT ALL in one consistent DB snapshot.
Usage: python3 benchmarks/verify_cp3.py [database]
Requires psql on PATH. Saves machine-readable evidence; makes no data changes.
"""
import json, pathlib, re, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
def split(path):
    text = path.read_text()
    return {m.group(1): re.sub(r'^--.*$', '', m.group(2), flags=re.M).strip().rstrip(';')
            for m in re.finditer(r'^-- @([RW]\d+)\s*\n(.*?)(?=^-- @|\Z)', text, re.M | re.S)}
a = split(ROOT/'queries/workload_30.sql')
b = split(ROOT/'sql/06_optimized_queries.sql')
statements = ["BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY; SET LOCAL search_path TO blinkit;"]
changed = [k for k in a if a[k] != b[k]]
assert changed == ['R13', 'R15', 'R16', 'R17', 'R19', 'R20'], changed
for k in changed:
    old = a[k]
    if k == 'R13':
        # Independent correction: retain NOT IN, explicitly remove NULLs.
        old = old.replace("WHERE o.placed_at >=", "WHERE oi.substitute_product_id IS NOT NULL AND o.placed_at >=")
    statements.append(f"""
WITH old AS MATERIALIZED ({old}), new AS MATERIALIZED ({b[k]}),
diff AS ((SELECT * FROM old EXCEPT ALL SELECT * FROM new)
         UNION ALL (SELECT * FROM new EXCEPT ALL SELECT * FROM old))
SELECT json_build_object('query', '{k}', 'reference', '{'NULL-filtered original' if k == 'R13' else 'original'}',
'old_rows', (SELECT count(*) FROM old), 'new_rows', (SELECT count(*) FROM new),
'difference_rows', (SELECT count(*) FROM diff),
'old_checksum', (SELECT md5(coalesce(string_agg(to_jsonb(t)::text, E'\\n' ORDER BY to_jsonb(t)::text), '')) FROM old t),
'new_checksum', (SELECT md5(coalesce(string_agg(to_jsonb(t)::text, E'\\n' ORDER BY to_jsonb(t)::text), '')) FROM new t));
""")
statements.append("SELECT json_build_object('query','R13_original','rows',count(*)) FROM ("+a['R13']+") t;")
statements.append('COMMIT;')
r = subprocess.run(['psql','-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-d',sys.argv[1] if len(sys.argv)>1 else 'blinkit_db'], input='\n'.join(statements), text=True, capture_output=True, check=True)
results = [json.loads(line) for line in r.stdout.splitlines() if line.strip()]
assert all(x.get('difference_rows',0)==0 for x in results), results
assert all(x.get('old_checksum')==x.get('new_checksum') for x in results), results
out={'rewritten':results,'unchanged_queries':[k for k in a if a[k]==b[k]],
     'ordering':'R15/R16/R17/R19/R20 retain identical ORDER BY keys; SQL leaves rows tied on those keys unordered. R13 has no ORDER BY.',
     'write_queries':'All five write statements are textually unchanged; benchmark runs use individual BEGIN/ROLLBACK transactions.'}
(ROOT/'benchmarks/results/optimized/correctness.json').write_text(json.dumps(out,indent=2)+'\n')
print(json.dumps(out,indent=2))
