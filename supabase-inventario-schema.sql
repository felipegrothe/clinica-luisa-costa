-- Execute no SQL Editor do Supabase para inventariar o esquema operacional
-- que ainda precisa ser convertido em migrations versionadas.

select
  c.table_name,
  c.ordinal_position,
  c.column_name,
  c.data_type,
  c.udt_name,
  c.is_nullable,
  c.column_default
from information_schema.columns c
where c.table_schema = 'public'
  and c.table_name in (
    'fin_lancamentos','fin_inadimplentes','itens','lotes','movimentacoes',
    'tirzepatida_frascos','tirzepatida_movimentacoes','fornecedores','setores',
    'auditoria','alertas_validade','comparativo_fornecedores'
  )
order by c.table_name, c.ordinal_position;

select
  tc.table_name,
  tc.constraint_name,
  tc.constraint_type,
  kcu.column_name,
  ccu.table_name as referenced_table,
  ccu.column_name as referenced_column
from information_schema.table_constraints tc
left join information_schema.key_column_usage kcu
  on kcu.constraint_schema=tc.constraint_schema and kcu.constraint_name=tc.constraint_name
left join information_schema.constraint_column_usage ccu
  on ccu.constraint_schema=tc.constraint_schema and ccu.constraint_name=tc.constraint_name
where tc.table_schema='public'
  and tc.table_name in (
    'fin_lancamentos','fin_inadimplentes','itens','lotes','movimentacoes',
    'tirzepatida_frascos','tirzepatida_movimentacoes','fornecedores','setores',
    'auditoria','alertas_validade','comparativo_fornecedores'
  )
order by tc.table_name, tc.constraint_name;
