-- Clinica Luisa Costa
-- Precificador no Supabase + cadastro publico de pacientes com foto.
-- Rode este arquivo no Supabase em SQL Editor.

grant usage on schema public to anon, authenticated;

-- Estado unico do Precificador.
-- Guarda precos, custos, categorias, modelos, sessoes e historico operacional
-- para todos os usuarios trabalharem sobre a mesma base.
create table if not exists public.precificador_state (
  id integer primary key default 1,
  state jsonb not null default '{}'::jsonb,
  updated_by uuid,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  constraint precificador_state_singleton check (id = 1)
);

alter table public.precificador_state enable row level security;
grant select, insert, update, delete on public.precificador_state to authenticated;

drop policy if exists "precificador_state_select_authenticated" on public.precificador_state;
drop policy if exists "precificador_state_insert_authenticated" on public.precificador_state;
drop policy if exists "precificador_state_update_authenticated" on public.precificador_state;
drop policy if exists "precificador_state_delete_authenticated" on public.precificador_state;

create policy "precificador_state_select_authenticated"
on public.precificador_state
for select
to authenticated
using (true);

create policy "precificador_state_insert_authenticated"
on public.precificador_state
for insert
to authenticated
with check (true);

create policy "precificador_state_update_authenticated"
on public.precificador_state
for update
to authenticated
using (true)
with check (true);

create policy "precificador_state_delete_authenticated"
on public.precificador_state
for delete
to authenticated
using (true);

insert into public.precificador_state (id, state)
values (1, '{}'::jsonb)
on conflict (id) do nothing;

-- Protocolos emitidos pelo Precificador.
create table if not exists public.protocolos (
  id uuid default gen_random_uuid() primary key,
  paciente_nome text not null,
  titulo text,
  valor_total numeric default 0,
  duracao integer,
  data_inicio date,
  data_fim date,
  status text default 'andamento',
  pagamento text,
  itens jsonb default '[]'::jsonb,
  sessoes jsonb default '[]'::jsonb,
  user_id uuid,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.protocolos add column if not exists paciente_nome text;
alter table public.protocolos add column if not exists titulo text;
alter table public.protocolos add column if not exists valor_total numeric default 0;
alter table public.protocolos add column if not exists duracao integer;
alter table public.protocolos add column if not exists data_inicio date;
alter table public.protocolos add column if not exists data_fim date;
alter table public.protocolos add column if not exists status text default 'andamento';
alter table public.protocolos add column if not exists pagamento text;
alter table public.protocolos add column if not exists itens jsonb default '[]'::jsonb;
alter table public.protocolos add column if not exists sessoes jsonb default '[]'::jsonb;
alter table public.protocolos add column if not exists user_id uuid;
alter table public.protocolos add column if not exists updated_at timestamptz default now();

alter table public.protocolos enable row level security;
grant select, insert, update, delete on public.protocolos to authenticated;

drop policy if exists "protocolos_select_authenticated" on public.protocolos;
drop policy if exists "protocolos_insert_authenticated" on public.protocolos;
drop policy if exists "protocolos_update_authenticated" on public.protocolos;
drop policy if exists "protocolos_delete_authenticated" on public.protocolos;

create policy "protocolos_select_authenticated"
on public.protocolos
for select
to authenticated
using (true);

create policy "protocolos_insert_authenticated"
on public.protocolos
for insert
to authenticated
with check (true);

create policy "protocolos_update_authenticated"
on public.protocolos
for update
to authenticated
using (true)
with check (true);

create policy "protocolos_delete_authenticated"
on public.protocolos
for delete
to authenticated
using (true);

-- Garante as colunas usadas pelo formulario publico de cadastro.
create table if not exists public.pacientes (
  id uuid default gen_random_uuid() primary key,
  nome text not null,
  cpf text,
  nascimento date,
  genero text,
  estado_civil text,
  profissao text,
  hobbies text,
  telefone text,
  email text,
  cep text,
  logradouro text,
  numero text,
  complemento text,
  bairro text,
  cidade text,
  estado text,
  altura numeric,
  peso_inicial numeric,
  medicamentos text,
  origem text,
  origem_indicador_nome text,
  objetivos text[],
  objetivo_outro text,
  foto_url text,
  relacionamento jsonb default '{}'::jsonb,
  consultas jsonb default '[]'::jsonb,
  protocolos jsonb default '[]'::jsonb,
  status text default 'ativo',
  cadastro_origem text default 'interno',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.pacientes add column if not exists cpf text;
alter table public.pacientes add column if not exists nascimento date;
alter table public.pacientes add column if not exists genero text;
alter table public.pacientes add column if not exists estado_civil text;
alter table public.pacientes add column if not exists profissao text;
alter table public.pacientes add column if not exists hobbies text;
alter table public.pacientes add column if not exists telefone text;
alter table public.pacientes add column if not exists email text;
alter table public.pacientes add column if not exists cep text;
alter table public.pacientes add column if not exists logradouro text;
alter table public.pacientes add column if not exists numero text;
alter table public.pacientes add column if not exists complemento text;
alter table public.pacientes add column if not exists bairro text;
alter table public.pacientes add column if not exists cidade text;
alter table public.pacientes add column if not exists estado text;
alter table public.pacientes add column if not exists altura numeric;
alter table public.pacientes add column if not exists peso_inicial numeric;
alter table public.pacientes add column if not exists medicamentos text;
alter table public.pacientes add column if not exists origem text;
alter table public.pacientes add column if not exists origem_indicador_nome text;
alter table public.pacientes add column if not exists objetivos text[];
alter table public.pacientes add column if not exists objetivo_outro text;
alter table public.pacientes add column if not exists foto_url text;
alter table public.pacientes add column if not exists relacionamento jsonb default '{}'::jsonb;
alter table public.pacientes add column if not exists consultas jsonb default '[]'::jsonb;
alter table public.pacientes add column if not exists protocolos jsonb default '[]'::jsonb;
alter table public.pacientes add column if not exists status text default 'ativo';
alter table public.pacientes add column if not exists cadastro_origem text default 'interno';
alter table public.pacientes add column if not exists updated_at timestamptz default now();

alter table public.pacientes enable row level security;
grant select, insert, update, delete on public.pacientes to authenticated;
grant insert on public.pacientes to anon;

drop policy if exists "pacientes_public_insert_cadastro" on public.pacientes;

create policy "pacientes_public_insert_cadastro"
on public.pacientes
for insert
to anon
with check (
  cadastro_origem = 'publico'
  and status = 'aguardando_revisao'
);

-- Bucket das fotos. Mantem publico para exibicao por URL, mas limita upload anonimo
-- ao prefixo publico/ usado pelo link de cadastro.
insert into storage.buckets (id, name, public)
values ('pacientes-fotos', 'pacientes-fotos', true)
on conflict (id) do update set public = true;

drop policy if exists "pacientes_fotos_select_public" on storage.objects;
drop policy if exists "pacientes_fotos_insert_authenticated" on storage.objects;
drop policy if exists "pacientes_fotos_update_authenticated" on storage.objects;
drop policy if exists "pacientes_fotos_delete_authenticated" on storage.objects;
drop policy if exists "pacientes_fotos_public_insert_cadastro" on storage.objects;

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

create policy "pacientes_fotos_public_insert_cadastro"
on storage.objects
for insert
to anon
with check (
  bucket_id = 'pacientes-fotos'
  and name like 'publico/%'
);
