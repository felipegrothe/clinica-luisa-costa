-- Clínica Luisa Costa — endurecimento de autorização/RLS.
-- Execute após os demais arquivos de estrutura. É idempotente.

create or replace function public.current_user_level()
returns text language sql stable security definer set search_path = public
as $$
  select lower(p.nivel) from public.perfis p
  where p.id = auth.uid() and p.ativo is true limit 1
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select coalesce(public.current_user_level() in ('admin','administrador'), false) $$;

create or replace function public.can_access_module(requested_module text)
returns boolean language sql stable security definer set search_path = public
as $$
  select coalesce(public.is_admin() or exists (
    select 1 from public.permissoes_modulos pm
    where lower(pm.nivel)=public.current_user_level()
      and pm.modulo=requested_module and pm.pode_acessar is true
  ), false)
$$;

grant execute on function public.current_user_level() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.can_access_module(text) to authenticated;

do $$
declare
  rec record;
  module_name text;
begin
  for rec in select * from (values
    ('agenda_eventos','agenda'),('agenda_configuracoes','agenda'),
    ('pacientes','pacientes'),('protocolos','precificador'),('precificador_state','precificador'),
    ('fin_lancamentos','financeiro'),('fin_inadimplentes','financeiro'),('fin_pagamentos','financeiro'),
    ('fin_estornos','financeiro'),('fin_auditoria','financeiro')
  ) as x(table_name,module_name)
  loop
    if exists (
      select 1
      from pg_catalog.pg_class c
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = rec.table_name
        and c.relkind in ('r', 'p')
    ) then
      module_name := rec.module_name;
      execute format('alter table public.%I enable row level security',rec.table_name);
      execute format('drop policy if exists %I on public.%I',rec.table_name||'_select_authenticated',rec.table_name);
      execute format('drop policy if exists %I on public.%I',rec.table_name||'_insert_authenticated',rec.table_name);
      execute format('drop policy if exists %I on public.%I',rec.table_name||'_update_authenticated',rec.table_name);
      execute format('drop policy if exists %I on public.%I',rec.table_name||'_delete_authenticated',rec.table_name);
      execute format('drop policy if exists %I on public.%I',rec.table_name||'_module_access',rec.table_name);
      execute format(
        'create policy %I on public.%I for all to authenticated using (public.can_access_module(%L)) with check (public.can_access_module(%L))',
        rec.table_name||'_module_access',rec.table_name,module_name,module_name
      );
    end if;
  end loop;
end $$;

-- O estoque não usa a política genérica FOR ALL. Execute
-- supabase-estoque-integridade.sql depois deste arquivo para instalar políticas
-- separadas de leitura, manutenção, aprovação e retirada transacional.

-- Remove também os nomes históricos usados pelos scripts específicos da agenda.
drop policy if exists "agenda_select_authenticated" on public.agenda_eventos;
drop policy if exists "agenda_insert_authenticated" on public.agenda_eventos;
drop policy if exists "agenda_update_authenticated" on public.agenda_eventos;
drop policy if exists "agenda_delete_authenticated" on public.agenda_eventos;
drop policy if exists "agenda_config_select_authenticated" on public.agenda_configuracoes;
drop policy if exists "agenda_config_insert_authenticated" on public.agenda_configuracoes;
drop policy if exists "agenda_config_update_authenticated" on public.agenda_configuracoes;
drop policy if exists "agenda_config_delete_authenticated" on public.agenda_configuracoes;

-- Administração: leitura limitada e escrita apenas para administradores.
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

create policy "config_clinica_select_active" on public.config_clinica for select to authenticated using (public.current_user_level() is not null);
create policy "config_clinica_write_admin" on public.config_clinica for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "config_sistema_select_active" on public.config_sistema for select to authenticated using (public.current_user_level() is not null);
create policy "config_sistema_write_admin" on public.config_sistema for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "perfis_select_self_or_admin" on public.perfis for select to authenticated using (id=auth.uid() or public.is_admin());
create policy "perfis_write_admin" on public.perfis for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "permissoes_select_active" on public.permissoes_modulos for select to authenticated using (public.current_user_level() is not null);
create policy "permissoes_write_admin" on public.permissoes_modulos for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "audit_logs_select_admin" on public.audit_logs for select to authenticated using (public.is_admin());
create policy "audit_logs_insert_self" on public.audit_logs for insert to authenticated with check (public.current_user_level() is not null and usuario_id=auth.uid());
