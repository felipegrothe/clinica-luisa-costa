-- Clinica Luisa Costa
-- Correcao da permissao do link publico de cadastro.
-- Rode este arquivo no Supabase em SQL Editor se o cadastro publico retornar erro de RLS.

grant usage on schema public to anon;
grant insert on public.pacientes to anon;
grant insert on public.pacientes to public;

alter table public.pacientes enable row level security;
alter table public.pacientes no force row level security;

drop policy if exists "pacientes_public_insert_cadastro" on public.pacientes;
drop policy if exists "pacientes_public_insert_cadastro_v2" on public.pacientes;
drop policy if exists "pacientes_public_insert_cadastro_v3" on public.pacientes;
drop policy if exists "pacientes_public_insert_cadastro_v4" on public.pacientes;

-- Libera apenas criacao publica. Nao libera leitura, edicao ou exclusao publica.
-- A validacao fina fica no app e a equipe revisa o cadastro antes de confirmar.
create policy "pacientes_public_insert_cadastro_v4"
on public.pacientes
for insert
to public
with check (true);

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
