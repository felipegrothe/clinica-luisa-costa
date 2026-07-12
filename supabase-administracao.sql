-- Clinica Luisa Costa
-- Estrutura inicial para o modulo Administracao.
-- Rode no Supabase em SQL Editor.

create table if not exists public.config_clinica (
  id integer primary key default 1,
  nome_clinica text,
  nome_fantasia text,
  cnpj text,
  email text,
  telefone text,
  whatsapp text,
  endereco text,
  medica_responsavel text,
  crm text,
  rqe text,
  rodape_documentos text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  constraint config_clinica_singleton check (id = 1)
);

create table if not exists public.config_sistema (
  id integer primary key default 1,
  duracao_protocolo_padrao integer default 12,
  alerta_renovacao_dias integer default 14,
  alerta_inatividade_dias integer default 90,
  alerta_aniversario_dias integer default 30,
  estoque_minimo_padrao integer default 2,
  alerta_validade_lote_dias integer default 60,
  integracoes jsonb default '{}'::jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  constraint config_sistema_singleton check (id = 1)
);

create table if not exists public.perfis (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text,
  email text,
  nivel text default 'colaborador',
  ativo boolean default true,
  criado_em timestamptz default now(),
  atualizado_em timestamptz default now()
);

alter table public.perfis add column if not exists nome text;
alter table public.perfis add column if not exists email text;
alter table public.perfis add column if not exists nivel text default 'colaborador';
alter table public.perfis add column if not exists ativo boolean default true;
alter table public.perfis add column if not exists criado_em timestamptz default now();
alter table public.perfis add column if not exists atualizado_em timestamptz default now();

create table if not exists public.permissoes_modulos (
  nivel text not null,
  modulo text not null,
  pode_acessar boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  primary key (nivel, modulo)
);

create table if not exists public.audit_logs (
  id uuid default gen_random_uuid() primary key,
  usuario_id uuid,
  usuario_nome text,
  tipo text default 'sistema',
  acao text not null,
  tabela text,
  registro_id text,
  dados_antes jsonb,
  dados_depois jsonb,
  created_at timestamptz default now()
);

alter table public.config_clinica enable row level security;
alter table public.config_sistema enable row level security;
alter table public.perfis enable row level security;
alter table public.permissoes_modulos enable row level security;
alter table public.audit_logs enable row level security;

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.config_clinica to authenticated;
grant select, insert, update, delete on public.config_sistema to authenticated;
grant select, insert, update, delete on public.perfis to authenticated;
grant select, insert, update, delete on public.permissoes_modulos to authenticated;
grant select, insert on public.audit_logs to authenticated;

create or replace function public.current_user_level()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select lower(p.nivel)
  from public.perfis p
  where p.id = auth.uid() and p.ativo is true
  limit 1
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_user_level() in ('admin','administrador'), false)
$$;

create or replace function public.can_access_module(requested_module text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    public.is_admin() or exists (
      select 1 from public.permissoes_modulos pm
      where lower(pm.nivel) = public.current_user_level()
        and pm.modulo = requested_module
        and pm.pode_acessar is true
    ), false
  )
$$;

grant execute on function public.current_user_level() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.can_access_module(text) to authenticated;

drop policy if exists "config_clinica_all_authenticated" on public.config_clinica;
drop policy if exists "config_sistema_all_authenticated" on public.config_sistema;
drop policy if exists "perfis_all_authenticated" on public.perfis;
drop policy if exists "permissoes_modulos_all_authenticated" on public.permissoes_modulos;
drop policy if exists "audit_logs_select_authenticated" on public.audit_logs;
drop policy if exists "audit_logs_insert_authenticated" on public.audit_logs;
drop policy if exists "config_clinica_select_active" on public.config_clinica;
drop policy if exists "config_clinica_write_admin" on public.config_clinica;
drop policy if exists "config_sistema_select_active" on public.config_sistema;
drop policy if exists "config_sistema_write_admin" on public.config_sistema;
drop policy if exists "perfis_select_self_or_admin" on public.perfis;
drop policy if exists "perfis_write_admin" on public.perfis;
drop policy if exists "permissoes_select_active" on public.permissoes_modulos;
drop policy if exists "permissoes_write_admin" on public.permissoes_modulos;
drop policy if exists "audit_logs_select_admin" on public.audit_logs;
drop policy if exists "audit_logs_insert_self" on public.audit_logs;

create policy "config_clinica_select_active" on public.config_clinica
for select to authenticated using (public.current_user_level() is not null);
create policy "config_clinica_write_admin" on public.config_clinica
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "config_sistema_select_active" on public.config_sistema
for select to authenticated using (public.current_user_level() is not null);
create policy "config_sistema_write_admin" on public.config_sistema
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "perfis_select_self_or_admin" on public.perfis
for select to authenticated using (id = auth.uid() or public.is_admin());
create policy "perfis_write_admin" on public.perfis
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "permissoes_select_active" on public.permissoes_modulos
for select to authenticated using (public.current_user_level() is not null);
create policy "permissoes_write_admin" on public.permissoes_modulos
for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "audit_logs_select_admin" on public.audit_logs
for select to authenticated using (public.is_admin());

create policy "audit_logs_insert_self" on public.audit_logs
for insert to authenticated
with check (public.current_user_level() is not null and usuario_id = auth.uid());

insert into public.config_clinica (id, nome_clinica, nome_fantasia)
values (1, 'Clínica Luisa Costa', 'Clínica Luisa Costa')
on conflict (id) do nothing;

insert into public.config_sistema (id)
values (1)
on conflict (id) do nothing;

insert into public.permissoes_modulos (nivel, modulo, pode_acessar)
values
('administrador','dashboard',true),
('administrador','agenda',true),
('administrador','precificador',true),
('administrador','pacientes',true),
('administrador','estoque',true),
('administrador','financeiro',true),
('administrador','prontuario',true),
('administrador','administracao',true),
('medico','dashboard',true),
('medico','agenda',true),
('medico','precificador',true),
('medico','pacientes',true),
('medico','estoque',false),
('medico','financeiro',false),
('medico','prontuario',true),
('medico','administracao',false),
('secretaria','dashboard',true),
('secretaria','agenda',true),
('secretaria','precificador',true),
('secretaria','pacientes',true),
('secretaria','estoque',false),
('secretaria','financeiro',false),
('secretaria','prontuario',false),
('secretaria','administracao',false),
('financeiro','dashboard',true),
('financeiro','agenda',false),
('financeiro','precificador',false),
('financeiro','pacientes',true),
('financeiro','estoque',false),
('financeiro','financeiro',true),
('financeiro','prontuario',false),
('financeiro','administracao',false),
('compras','dashboard',true),
('compras','agenda',false),
('compras','precificador',false),
('compras','pacientes',false),
('compras','estoque',true),
('compras','financeiro',false),
('compras','prontuario',false),
('compras','administracao',false),
('colaborador','dashboard',true),
('colaborador','agenda',false),
('colaborador','precificador',false),
('colaborador','pacientes',true),
('colaborador','estoque',false),
('colaborador','financeiro',false),
('colaborador','prontuario',false),
('colaborador','administracao',false)
on conflict (nivel, modulo) do nothing;
