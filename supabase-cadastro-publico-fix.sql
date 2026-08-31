-- Clinica Luisa Costa
-- Desativa o antigo INSERT público direto.
-- O cadastro público deve usar somente a RPC criar_paciente_publico(jsonb).

grant usage on schema public to anon;
revoke insert on public.pacientes from anon;
revoke insert on public.pacientes from public;

alter table public.pacientes enable row level security;
alter table public.pacientes no force row level security;

drop policy if exists "pacientes_public_insert_cadastro" on public.pacientes;
drop policy if exists "pacientes_public_insert_cadastro_v2" on public.pacientes;
drop policy if exists "pacientes_public_insert_cadastro_v3" on public.pacientes;
drop policy if exists "pacientes_public_insert_cadastro_v4" on public.pacientes;

notify pgrst, 'reload schema';

select
  policyname,
  permissive,
  roles,
  cmd,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'pacientes'
order by policyname;
