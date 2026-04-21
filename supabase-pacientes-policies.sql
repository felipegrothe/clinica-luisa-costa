-- Clinica Luisa Costa
-- Policies iniciais para o modulo Pacientes.
-- Rode este arquivo no Supabase em SQL Editor.

alter table public.pacientes enable row level security;

drop policy if exists "pacientes_select_authenticated" on public.pacientes;
drop policy if exists "pacientes_insert_authenticated" on public.pacientes;
drop policy if exists "pacientes_update_authenticated" on public.pacientes;
drop policy if exists "pacientes_delete_authenticated" on public.pacientes;

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.pacientes to authenticated;

create policy "pacientes_select_authenticated"
on public.pacientes
for select
to authenticated
using (true);

create policy "pacientes_insert_authenticated"
on public.pacientes
for insert
to authenticated
with check (true);

create policy "pacientes_update_authenticated"
on public.pacientes
for update
to authenticated
using (true)
with check (true);

create policy "pacientes_delete_authenticated"
on public.pacientes
for delete
to authenticated
using (true);

-- Storage das fotos dos pacientes.
-- Se estas policies ja existirem no bucket pacientes-fotos, os comandos abaixo apenas recriam o mesmo acesso.
drop policy if exists "pacientes_fotos_select_public" on storage.objects;
drop policy if exists "pacientes_fotos_insert_authenticated" on storage.objects;
drop policy if exists "pacientes_fotos_update_authenticated" on storage.objects;
drop policy if exists "pacientes_fotos_delete_authenticated" on storage.objects;

create policy "pacientes_fotos_select_public"
on storage.objects
for select
to public
using (bucket_id = 'pacientes-fotos');

create policy "pacientes_fotos_insert_authenticated"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'pacientes-fotos');

create policy "pacientes_fotos_update_authenticated"
on storage.objects
for update
to authenticated
using (bucket_id = 'pacientes-fotos')
with check (bucket_id = 'pacientes-fotos');

create policy "pacientes_fotos_delete_authenticated"
on storage.objects
for delete
to authenticated
using (bucket_id = 'pacientes-fotos');
