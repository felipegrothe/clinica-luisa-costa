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
  t text;
  tables text[] := array[
    'pacientes',
    'protocolos',
    'fin_lancamentos',
    'fin_inadimplentes',
    'itens',
    'lotes',
    'movimentacoes',
    'tirzepatida_frascos',
    'tirzepatida_movimentacoes',
    'fornecedores',
    'setores',
    'auditoria',
    'audit_logs'
  ];
begin
  foreach t in array tables loop
    if to_regclass('public.' || t) is not null then
      execute format('alter table public.%I enable row level security', t);
      execute format('grant select, insert, update, delete on public.%I to authenticated', t);

      execute format('drop policy if exists %I on public.%I', t || '_select_authenticated', t);
      execute format('drop policy if exists %I on public.%I', t || '_insert_authenticated', t);
      execute format('drop policy if exists %I on public.%I', t || '_update_authenticated', t);
      execute format('drop policy if exists %I on public.%I', t || '_delete_authenticated', t);

      execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_select_authenticated', t);
      execute format('create policy %I on public.%I for insert to authenticated with check (true)', t || '_insert_authenticated', t);
      execute format('create policy %I on public.%I for update to authenticated using (true) with check (true)', t || '_update_authenticated', t);
      execute format('create policy %I on public.%I for delete to authenticated using (true)', t || '_delete_authenticated', t);
    end if;
  end loop;
end $$;
