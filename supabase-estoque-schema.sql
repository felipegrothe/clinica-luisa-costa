-- Clínica Luisa Costa — estrutura versionada do módulo de estoque.
-- Seguro para bancos existentes: CREATE/ADD usam IF NOT EXISTS.

begin;

create extension if not exists pgcrypto;

create table if not exists public.setores (
  id uuid primary key default gen_random_uuid(),
  nome text not null unique,
  ordem integer not null default 0,
  criado_em timestamptz not null default now()
);

create table if not exists public.fornecedores (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  tipo text not null default 'farmacia',
  contato text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table if not exists public.itens (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  unidade text not null default 'un',
  amp_por_caixa numeric not null default 1 check (amp_por_caixa>0),
  estoque_min numeric not null default 0 check (estoque_min>=0),
  estoque_ideal numeric not null default 0 check (estoque_ideal>=0),
  usado_total numeric not null default 0 check (usado_total>=0),
  preco_unitario numeric not null default 0 check (preco_unitario>=0),
  setor_id uuid references public.setores(id),
  fornecedor_id uuid references public.fornecedores(id),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table if not exists public.lotes (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.itens(id),
  fornecedor_id uuid references public.fornecedores(id),
  numero_lote text,
  validade date not null,
  quantidade_cx numeric not null check (quantidade_cx>0),
  amp_por_caixa numeric not null default 1 check (amp_por_caixa>0),
  usado_base numeric not null default 0 check (usado_base>=0),
  preco_total numeric not null default 0 check (preco_total>=0),
  observacoes text,
  status text not null default 'pendente' check (status in ('pendente','aprovado','rejeitado','descartado')),
  criado_por uuid,
  aprovado_por uuid,
  aprovado_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

alter table public.lotes add column if not exists preco_por_cx numeric
generated always as (case when quantidade_cx>0 then preco_total/quantidade_cx else 0 end) stored;

create table if not exists public.movimentacoes (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.itens(id),
  tipo text not null check (tipo in ('entrada','saida','ajuste')),
  quantidade numeric not null check (quantidade>0),
  data date not null default current_date,
  motivo text not null,
  responsavel_id uuid,
  responsavel_nome text,
  criado_em timestamptz not null default now()
);

create table if not exists public.tirzepatida_frascos (
  id uuid primary key default gen_random_uuid(),
  mg numeric not null default 0 check (mg>=0),
  fornecedor_id uuid references public.fornecedores(id),
  numero_lote text,
  validade date not null,
  ampolas_total numeric not null check (ampolas_total>0),
  ampolas_usadas numeric not null default 0 check (ampolas_usadas>=0 and ampolas_usadas<=ampolas_total),
  preco_pago numeric not null default 0 check (preco_pago>=0),
  observacoes text,
  estoque_min_ampolas numeric not null default 0 check (estoque_min_ampolas>=0),
  estoque_ideal_ampolas numeric not null default 0 check (estoque_ideal_ampolas>=0),
  status text not null default 'ativo' check (status in ('ativo','descartado')),
  criado_por uuid,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

alter table public.tirzepatida_frascos add column if not exists ampolas_disp numeric
generated always as (greatest(0,ampolas_total-ampolas_usadas)) stored;
alter table public.tirzepatida_frascos add column if not exists preco_por_amp numeric
generated always as (case when ampolas_total>0 then preco_pago/ampolas_total else 0 end) stored;

create table if not exists public.tirzepatida_movimentacoes (
  id uuid primary key default gen_random_uuid(),
  frasco_id uuid not null references public.tirzepatida_frascos(id),
  tipo text not null check (tipo in ('entrada','saida','ajuste')),
  quantidade numeric not null check (quantidade>0),
  data date not null default current_date,
  motivo text not null,
  responsavel_id uuid,
  responsavel_nome text,
  criado_em timestamptz not null default now()
);

create table if not exists public.auditoria (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid,
  usuario_nome text,
  acao text not null,
  tabela text,
  registro_id uuid,
  dados_antes jsonb,
  dados_depois jsonb,
  criado_em timestamptz not null default now()
);

create index if not exists idx_lotes_item_status_validade on public.lotes(item_id,status,validade);
create index if not exists idx_movimentacoes_item_data on public.movimentacoes(item_id,data desc);
create index if not exists idx_tirzepatida_status_validade on public.tirzepatida_frascos(status,validade);
create index if not exists idx_tirzepatida_mov_frasco_data on public.tirzepatida_movimentacoes(frasco_id,data desc);
do $$
begin
  if not exists(select 1 from public.itens where ativo is true group by setor_id,lower(btrim(nome)) having count(*)>1) then
    create unique index if not exists idx_itens_nome_setor_ativo on public.itens(setor_id,lower(btrim(nome))) where ativo is true;
  else
    raise notice 'Índice único de itens adiado: existem nomes duplicados a revisar.';
  end if;
  if not exists(select 1 from public.fornecedores group by lower(btrim(nome)) having count(*)>1) then
    create unique index if not exists idx_fornecedores_nome_normalizado on public.fornecedores(lower(btrim(nome)));
  else
    raise notice 'Índice único de fornecedores adiado: existem nomes duplicados a revisar.';
  end if;
end $$;

-- CREATE OR REPLACE VIEW não aceita mudanças na ordem ou no nome das colunas.
-- Removemos somente as views antigas, em ordem de dependência, e as recriamos
-- abaixo dentro da mesma transação. Nenhum dado das tabelas é removido.
drop view if exists public.dashboard;
drop view if exists public.alertas_validade;
drop view if exists public.comparativo_fornecedores;
drop view if exists public.estoque_atual;

create or replace view public.estoque_atual
with (security_invoker=true)
as
with la as (
  select l.item_id,
    coalesce(sum(greatest(0,l.quantidade_cx*l.amp_por_caixa-l.usado_base)) filter (where l.status='aprovado'),0) as disponivel,
    min(l.validade) filter (where l.status='aprovado' and l.quantidade_cx*l.amp_por_caixa-l.usado_base>0) as proxima_validade,
    avg(l.preco_por_cx) filter (where l.status='aprovado' and l.preco_por_cx>0) as preco_medio_cx,
    coalesce(sum(greatest(0,l.quantidade_cx*l.amp_por_caixa-l.usado_base)
      * case when l.quantidade_cx*l.amp_por_caixa>0 then l.preco_total/(l.quantidade_cx*l.amp_por_caixa) else 0 end)
      filter (where l.status='aprovado'),0) as custo_estoque
  from public.lotes l group by l.item_id
)
select i.*,s.nome as setor,coalesce(la.disponivel,0) as disponivel,la.proxima_validade,
  coalesce(la.preco_medio_cx,0) as preco_medio_cx,coalesce(la.custo_estoque,0) as custo_estoque,
  coalesce((select l.preco_por_cx from public.lotes l where l.item_id=i.id and l.status='aprovado' order by l.criado_em desc limit 1),0) as ultimo_preco_cx,
  case when la.proxima_validade is null then 'ok' when la.proxima_validade<current_date then 'vencido'
       when la.proxima_validade<=current_date+30 then 'critico' when la.proxima_validade<=current_date+90 then 'atencao' else 'ok' end as status_validade,
  case when coalesce(la.disponivel,0)<=coalesce(i.estoque_min,0) then 'critico' else 'ok' end as status_estoque
from public.itens i left join public.setores s on s.id=i.setor_id left join la on la.item_id=i.id;

create or replace view public.alertas_validade
with (security_invoker=true)
as
select l.id as lote_id,l.item_id,i.nome as item_nome,l.numero_lote,l.validade,
       (l.validade-current_date) as dias_para_vencer,
       greatest(0,l.quantidade_cx*l.amp_por_caixa-l.usado_base) as disponivel
from public.lotes l join public.itens i on i.id=l.item_id
where l.status='aprovado' and i.ativo is true
  and l.quantidade_cx*l.amp_por_caixa-l.usado_base>0
  and l.validade<=current_date+90
order by l.validade,l.criado_em;

create or replace view public.comparativo_fornecedores
with (security_invoker=true)
as
select i.id as item_id,i.nome as item_nome,f.id as fornecedor_id,f.nome as fornecedor,
       count(*) as total_compras,avg(l.preco_por_cx) as preco_medio_cx,min(l.preco_por_cx) as menor_preco
from public.lotes l join public.itens i on i.id=l.item_id join public.fornecedores f on f.id=l.fornecedor_id
where l.status='aprovado' and l.preco_por_cx>0
group by i.id,i.nome,f.id,f.nome;

create or replace view public.dashboard
with (security_invoker=true)
as
select coalesce(sum(e.custo_estoque),0) as valor_total_estoque,
       count(*) filter (where e.ativo and e.status_validade='vencido') as itens_vencidos,
       count(*) filter (where e.ativo and e.status_validade='critico') as itens_vencendo,
       count(*) filter (where e.ativo and e.status_estoque='critico') as itens_estoque_minimo,
       (select count(*) from public.lotes where status='pendente') as nfs_pendentes_aprovacao
from public.estoque_atual e;

grant select on public.estoque_atual,public.alertas_validade,public.comparativo_fornecedores,public.dashboard to authenticated;

commit;
