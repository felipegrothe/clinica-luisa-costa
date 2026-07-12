-- Clinica Luisa Costa
-- Policies operacionais para reduzir risco de falha de salvamento.
-- Rode no Supabase em SQL Editor antes do uso em equipe.

-- Protocolos usados pelo Precificador, Pacientes e Financeiro.
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

do $$
declare
  rec record;
begin
  for rec in select * from (values
    ('pacientes','pacientes'),('protocolos','precificador'),
    ('fin_lancamentos','financeiro'),('fin_inadimplentes','financeiro'),
    ('itens','estoque'),('lotes','estoque'),('movimentacoes','estoque'),
    ('tirzepatida_frascos','estoque'),('tirzepatida_movimentacoes','estoque'),
    ('fornecedores','estoque'),('setores','estoque'),('auditoria','estoque')
  ) as x(table_name,module_name)
  loop
    if to_regclass('public.' || rec.table_name) is not null then
      execute format('alter table public.%I enable row level security', rec.table_name);
      execute format('grant select, insert, update, delete on public.%I to authenticated', rec.table_name);

      execute format('drop policy if exists %I on public.%I', rec.table_name || '_select_authenticated', rec.table_name);
      execute format('drop policy if exists %I on public.%I', rec.table_name || '_insert_authenticated', rec.table_name);
      execute format('drop policy if exists %I on public.%I', rec.table_name || '_update_authenticated', rec.table_name);
      execute format('drop policy if exists %I on public.%I', rec.table_name || '_delete_authenticated', rec.table_name);
      execute format('drop policy if exists %I on public.%I', rec.table_name || '_module_access', rec.table_name);

      execute format(
        'create policy %I on public.%I for all to authenticated using (public.can_access_module(%L)) with check (public.can_access_module(%L))',
        rec.table_name || '_module_access', rec.table_name, rec.module_name, rec.module_name
      );
    end if;
  end loop;
end $$;
