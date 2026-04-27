-- Agenda da Clínica Luisa Costa
-- Rode este arquivo no SQL Editor do Supabase.

create table if not exists public.agenda_eventos (
  id uuid primary key default gen_random_uuid(),
  paciente_id uuid references public.pacientes(id) on delete set null,
  paciente_nome text not null,
  telefone text,
  data date not null,
  hora_inicio time not null,
  hora_fim time,
  duracao_min integer default 60,
  profissional text not null default 'dra_luisa',
  tipo text default 'Consulta',
  status text not null default 'aguardando_confirmacao',
  sala text,
  observacoes text,
  primeira_consulta boolean default false,
  cor text,
  recorrencia jsonb,
  created_by uuid default auth.uid(),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.agenda_eventos add column if not exists cor text;
alter table public.agenda_eventos add column if not exists recorrencia jsonb;

create table if not exists public.agenda_configuracoes (
  chave text primary key,
  valor jsonb not null,
  updated_at timestamptz default now()
);

alter table public.agenda_eventos enable row level security;
alter table public.agenda_configuracoes enable row level security;

drop policy if exists "agenda_select_authenticated" on public.agenda_eventos;
drop policy if exists "agenda_insert_authenticated" on public.agenda_eventos;
drop policy if exists "agenda_update_authenticated" on public.agenda_eventos;
drop policy if exists "agenda_delete_authenticated" on public.agenda_eventos;
drop policy if exists "agenda_config_select_authenticated" on public.agenda_configuracoes;
drop policy if exists "agenda_config_insert_authenticated" on public.agenda_configuracoes;
drop policy if exists "agenda_config_update_authenticated" on public.agenda_configuracoes;
drop policy if exists "agenda_config_delete_authenticated" on public.agenda_configuracoes;

create policy "agenda_select_authenticated"
on public.agenda_eventos
for select
to authenticated
using (true);

create policy "agenda_insert_authenticated"
on public.agenda_eventos
for insert
to authenticated
with check (true);

create policy "agenda_update_authenticated"
on public.agenda_eventos
for update
to authenticated
using (true)
with check (true);

create policy "agenda_delete_authenticated"
on public.agenda_eventos
for delete
to authenticated
using (true);

create policy "agenda_config_select_authenticated"
on public.agenda_configuracoes
for select
to authenticated
using (true);

create policy "agenda_config_insert_authenticated"
on public.agenda_configuracoes
for insert
to authenticated
with check (true);

create policy "agenda_config_update_authenticated"
on public.agenda_configuracoes
for update
to authenticated
using (true)
with check (true);

create policy "agenda_config_delete_authenticated"
on public.agenda_configuracoes
for delete
to authenticated
using (true);

create index if not exists agenda_eventos_data_idx on public.agenda_eventos(data);
create index if not exists agenda_eventos_profissional_idx on public.agenda_eventos(profissional);
create index if not exists agenda_eventos_paciente_idx on public.agenda_eventos(paciente_id);

create or replace function public.update_agenda_eventos_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists agenda_eventos_updated_at on public.agenda_eventos;
create trigger agenda_eventos_updated_at
before update on public.agenda_eventos
for each row execute function public.update_agenda_eventos_updated_at();

create or replace function public.update_agenda_configuracoes_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists agenda_configuracoes_updated_at on public.agenda_configuracoes;
create trigger agenda_configuracoes_updated_at
before update on public.agenda_configuracoes
for each row execute function public.update_agenda_configuracoes_updated_at();
