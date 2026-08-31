-- Clínica Luisa Costa — Tratamentos, aplicações e rastreabilidade.
-- Migração aditiva: preserva o Precificador e os protocolos já existentes.

begin;

create extension if not exists pgcrypto;

alter table public.protocolos
  add column if not exists paciente_id uuid references public.pacientes(id) on delete set null;

create index if not exists protocolos_paciente_id_idx on public.protocolos(paciente_id);

create table if not exists public.tratamento_planos (
  id uuid primary key default gen_random_uuid(),
  paciente_id uuid not null references public.pacientes(id) on delete restrict,
  paciente_nome_snapshot text not null,
  protocolo_id uuid references public.protocolos(id) on delete set null,
  origem text not null default 'manual' check (origem in ('manual','precificador')),
  nome text not null,
  sessoes_planejadas integer not null check (sessoes_planejadas > 0),
  data_inicio date,
  frequencia text,
  status text not null default 'planejado' check (status in ('planejado','andamento','concluido','cancelado')),
  observacoes text,
  idempotency_key uuid not null default gen_random_uuid(),
  criado_por uuid not null default auth.uid(),
  atualizado_por uuid not null default auth.uid(),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create unique index if not exists tratamento_planos_idempotency_uidx
  on public.tratamento_planos(idempotency_key);

create table if not exists public.tratamento_plano_itens (
  id uuid primary key default gen_random_uuid(),
  plano_id uuid not null references public.tratamento_planos(id) on delete cascade,
  item_id uuid references public.itens(id) on delete set null,
  ativo_nome text not null,
  dose_prevista numeric check (dose_prevista is null or dose_prevista > 0),
  unidade text,
  via text,
  observacoes text,
  criado_em timestamptz not null default now()
);

create table if not exists public.tratamento_aplicacoes (
  id uuid primary key default gen_random_uuid(),
  paciente_id uuid not null references public.pacientes(id) on delete restrict,
  paciente_nome_snapshot text not null,
  plano_id uuid references public.tratamento_planos(id) on delete set null,
  protocolo_id uuid references public.protocolos(id) on delete set null,
  tipo text not null default 'avulsa' check (tipo in ('plano','avulsa')),
  sessao_numero integer check (sessao_numero is null or sessao_numero > 0),
  sessoes_total integer check (sessoes_total is null or sessoes_total > 0),
  aplicada_em timestamptz not null,
  profissional text not null,
  observacoes text,
  intercorrencias text,
  status text not null default 'realizada' check (status in ('realizada','cancelada','retificada')),
  idempotency_key uuid not null,
  criado_por uuid not null default auth.uid(),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint tratamento_aplicacoes_sessao_limite check (
    sessao_numero is null or sessoes_total is null or sessao_numero <= sessoes_total
  )
);

create unique index if not exists tratamento_aplicacoes_idempotency_uidx
  on public.tratamento_aplicacoes(idempotency_key);
create unique index if not exists tratamento_aplicacoes_plano_sessao_realizada_uidx
  on public.tratamento_aplicacoes(plano_id,sessao_numero)
  where plano_id is not null and sessao_numero is not null and status='realizada';

create table if not exists public.tratamento_aplicacao_itens (
  id uuid primary key default gen_random_uuid(),
  aplicacao_id uuid not null references public.tratamento_aplicacoes(id) on delete restrict,
  item_id uuid references public.itens(id) on delete set null,
  lote_id uuid references public.lotes(id) on delete restrict,
  ativo_nome text not null,
  dose numeric not null check (dose > 0),
  unidade text not null,
  via text,
  quantidade_estoque numeric not null default 1 check (quantidade_estoque > 0),
  lote_numero_snapshot text not null,
  validade_snapshot date,
  fabricante_snapshot text,
  origem_lote text not null default 'estoque' check (origem_lote in ('estoque','manual_legado')),
  criado_em timestamptz not null default now(),
  constraint tratamento_item_lote_coerente check (
    (origem_lote = 'estoque' and lote_id is not null)
    or (origem_lote = 'manual_legado' and lote_id is null)
  )
);

create table if not exists public.tratamento_auditoria (
  id bigint generated always as identity primary key,
  tabela text not null,
  registro_id uuid not null,
  acao text not null check (acao in ('insert','update')),
  dados_antes jsonb,
  dados_depois jsonb,
  usuario_id uuid default auth.uid(),
  criado_em timestamptz not null default now()
);

create index if not exists tratamento_planos_paciente_idx
  on public.tratamento_planos(paciente_id, criado_em desc);
create index if not exists tratamento_aplicacoes_paciente_data_idx
  on public.tratamento_aplicacoes(paciente_id, aplicada_em desc);
create index if not exists tratamento_aplicacoes_plano_idx
  on public.tratamento_aplicacoes(plano_id, sessao_numero);
create index if not exists tratamento_aplicacao_itens_lote_idx
  on public.tratamento_aplicacao_itens(lote_id);
create index if not exists tratamento_aplicacao_itens_ativo_idx
  on public.tratamento_aplicacao_itens(lower(ativo_nome));

create or replace function public.tratamento_auditar_registro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.tratamento_auditoria(tabela, registro_id, acao, dados_antes, dados_depois, usuario_id)
  values (tg_table_name, new.id, lower(tg_op), case when tg_op='UPDATE' then to_jsonb(old) end, to_jsonb(new), auth.uid());
  return new;
end;
$$;

drop trigger if exists tratamento_planos_auditoria on public.tratamento_planos;
create trigger tratamento_planos_auditoria
after insert or update on public.tratamento_planos
for each row execute function public.tratamento_auditar_registro();

drop trigger if exists tratamento_aplicacoes_auditoria on public.tratamento_aplicacoes;
create trigger tratamento_aplicacoes_auditoria
after insert or update on public.tratamento_aplicacoes
for each row execute function public.tratamento_auditar_registro();

create or replace function public.registrar_tratamento_aplicacao(
  p_paciente_id uuid,
  p_plano_id uuid,
  p_tipo text,
  p_sessao_numero integer,
  p_sessoes_total integer,
  p_aplicada_em timestamptz,
  p_profissional text,
  p_observacoes text,
  p_intercorrencias text,
  p_idempotency_key uuid,
  p_itens jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_aplicacao_id uuid;
  v_paciente_nome text;
  v_item jsonb;
  v_lote public.lotes%rowtype;
  v_item_nome text;
  v_fabricante text;
  v_disponivel numeric;
  v_qtd numeric;
  v_origem text;
  v_plano_paciente uuid;
  v_plano_sessoes integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text,0));
  if auth.uid() is null or not public.can_access_module('precificador') then
    raise exception 'Sem permissão para registrar aplicações.' using errcode='42501';
  end if;
  if p_tipo not in ('plano','avulsa') then raise exception 'Tipo de aplicação inválido.'; end if;
  if p_tipo='plano' and p_plano_id is null then raise exception 'Selecione o plano de aplicação.'; end if;
  if p_aplicada_em > now()+interval '5 minutes' then raise exception 'A aplicação realizada não pode ter data futura.'; end if;
  if nullif(btrim(p_profissional),'') is null then raise exception 'Informe o profissional responsável.'; end if;
  if p_aplicada_em is null then raise exception 'Informe data e hora da aplicação.'; end if;
  if jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens)=0 then
    raise exception 'Informe pelo menos um medicamento aplicado.';
  end if;

  select nome into v_paciente_nome from public.pacientes where id=p_paciente_id;
  if v_paciente_nome is null then raise exception 'Paciente não encontrado.'; end if;
  if p_tipo='plano' then
    select paciente_id,sessoes_planejadas into v_plano_paciente,v_plano_sessoes
    from public.tratamento_planos where id=p_plano_id and status in ('planejado','andamento');
    if v_plano_paciente is null then raise exception 'Plano não encontrado ou indisponível.'; end if;
    if v_plano_paciente<>p_paciente_id then raise exception 'O plano não pertence ao paciente selecionado.'; end if;
    if p_sessao_numero is null or p_sessao_numero>v_plano_sessoes then raise exception 'Número da sessão inválido para este plano.'; end if;
  end if;

  select id into v_aplicacao_id
  from public.tratamento_aplicacoes where idempotency_key=p_idempotency_key;
  if v_aplicacao_id is not null then return v_aplicacao_id; end if;

  insert into public.tratamento_aplicacoes(
    paciente_id,paciente_nome_snapshot,plano_id,tipo,sessao_numero,sessoes_total,
    aplicada_em,profissional,observacoes,intercorrencias,idempotency_key,criado_por
  ) values (
    p_paciente_id,v_paciente_nome,p_plano_id,p_tipo,p_sessao_numero,p_sessoes_total,
    p_aplicada_em,btrim(p_profissional),nullif(btrim(p_observacoes),''),
    nullif(btrim(p_intercorrencias),''),p_idempotency_key,auth.uid()
  ) returning id into v_aplicacao_id;

  for v_item in select value from jsonb_array_elements(p_itens)
  loop
    v_qtd := coalesce(nullif((v_item->>'quantidade_estoque')::numeric,0),1);
    v_origem := coalesce(nullif(v_item->>'origem_lote',''),'estoque');
    if coalesce((v_item->>'dose')::numeric,0)<=0 then raise exception 'Dose inválida.'; end if;
    if nullif(btrim(v_item->>'unidade'),'') is null then raise exception 'Unidade da dose obrigatória.'; end if;

    if v_origem='estoque' then
      select l.* into v_lote from public.lotes l where l.id=(v_item->>'lote_id')::uuid for update;
      if not found then raise exception 'Lote não encontrado.'; end if;
      if v_lote.status <> 'aprovado' then raise exception 'O lote selecionado não está aprovado.'; end if;
      if v_lote.validade < p_aplicada_em::date then raise exception 'Não é permitido aplicar lote vencido.'; end if;
      v_disponivel := greatest(0,v_lote.quantidade_cx*v_lote.amp_por_caixa-v_lote.usado_base);
      if v_disponivel < v_qtd then raise exception 'Saldo insuficiente no lote %.',coalesce(v_lote.numero_lote,'sem número'); end if;
      select i.nome, f.nome into v_item_nome,v_fabricante
      from public.itens i left join public.fornecedores f on f.id=v_lote.fornecedor_id
      where i.id=v_lote.item_id;

      insert into public.tratamento_aplicacao_itens(
        aplicacao_id,item_id,lote_id,ativo_nome,dose,unidade,via,quantidade_estoque,
        lote_numero_snapshot,validade_snapshot,fabricante_snapshot,origem_lote
      ) values (
        v_aplicacao_id,v_lote.item_id,v_lote.id,coalesce(v_item_nome,v_item->>'ativo_nome'),
        (v_item->>'dose')::numeric,btrim(v_item->>'unidade'),nullif(btrim(v_item->>'via'),''),v_qtd,
        coalesce(nullif(v_lote.numero_lote,''),'SEM NÚMERO'),v_lote.validade,v_fabricante,'estoque'
      );

      update public.lotes set usado_base=usado_base+v_qtd, atualizado_em=now() where id=v_lote.id;
      insert into public.movimentacoes(item_id,tipo,quantidade,data,motivo,responsavel_id,responsavel_nome)
      values(v_lote.item_id,'saida',v_qtd,p_aplicada_em::date,'Aplicação em paciente · registro '||v_aplicacao_id,auth.uid(),btrim(p_profissional));
    else
      if nullif(btrim(v_item->>'ativo_nome'),'') is null or nullif(btrim(v_item->>'lote_numero'),'') is null then
        raise exception 'Ativo e número do lote são obrigatórios no registro legado.';
      end if;
      insert into public.tratamento_aplicacao_itens(
        aplicacao_id,ativo_nome,dose,unidade,via,quantidade_estoque,lote_numero_snapshot,
        validade_snapshot,fabricante_snapshot,origem_lote
      ) values (
        v_aplicacao_id,btrim(v_item->>'ativo_nome'),(v_item->>'dose')::numeric,
        btrim(v_item->>'unidade'),nullif(btrim(v_item->>'via'),''),v_qtd,btrim(v_item->>'lote_numero'),
        nullif(v_item->>'validade','')::date,nullif(btrim(v_item->>'fabricante'),''),'manual_legado'
      );
    end if;
  end loop;

  return v_aplicacao_id;
end;
$$;

create or replace function public.salvar_tratamento_plano(
  p_paciente_id uuid,
  p_nome text,
  p_sessoes_planejadas integer,
  p_data_inicio date,
  p_frequencia text,
  p_observacoes text,
  p_origem text,
  p_protocolo_id uuid,
  p_idempotency_key uuid,
  p_itens jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plano_id uuid;
  v_paciente_nome text;
  v_item jsonb;
  v_item_nome text;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text,0));
  if auth.uid() is null or not public.can_access_module('precificador') then
    raise exception 'Sem permissão para criar planos.' using errcode='42501';
  end if;
  if nullif(btrim(p_nome),'') is null then raise exception 'Informe o nome do plano.'; end if;
  if p_origem not in ('manual','precificador') then raise exception 'Origem do plano inválida.'; end if;
  if coalesce(p_sessoes_planejadas,0)<=0 then raise exception 'Número de sessões inválido.'; end if;
  if jsonb_typeof(p_itens)<>'array' or jsonb_array_length(p_itens)=0 then
    raise exception 'Informe pelo menos um ativo no plano.';
  end if;
  select nome into v_paciente_nome from public.pacientes where id=p_paciente_id;
  if v_paciente_nome is null then raise exception 'Paciente não encontrado.'; end if;
  select id into v_plano_id from public.tratamento_planos where idempotency_key=p_idempotency_key;
  if v_plano_id is not null then return v_plano_id; end if;

  insert into public.tratamento_planos(
    paciente_id,paciente_nome_snapshot,protocolo_id,origem,nome,sessoes_planejadas,data_inicio,
    frequencia,observacoes,idempotency_key,criado_por,atualizado_por
  ) values (
    p_paciente_id,v_paciente_nome,p_protocolo_id,p_origem,btrim(p_nome),p_sessoes_planejadas,p_data_inicio,
    nullif(btrim(p_frequencia),''),nullif(btrim(p_observacoes),''),p_idempotency_key,auth.uid(),auth.uid()
  ) returning id into v_plano_id;

  for v_item in select value from jsonb_array_elements(p_itens)
  loop
    if nullif(v_item->>'item_id','') is not null then
      select nome into v_item_nome from public.itens where id=(v_item->>'item_id')::uuid and ativo is true;
    else
      v_item_nome := nullif(btrim(v_item->>'ativo_nome'),'');
    end if;
    if v_item_nome is null then raise exception 'Ativo do plano inválido.'; end if;
    insert into public.tratamento_plano_itens(plano_id,item_id,ativo_nome,dose_prevista,unidade,via,observacoes)
    values(v_plano_id,nullif(v_item->>'item_id','')::uuid,v_item_nome,
      nullif(v_item->>'dose','')::numeric,nullif(btrim(v_item->>'unidade'),''),
      nullif(btrim(v_item->>'via'),''),nullif(btrim(v_item->>'observacoes'),''));
  end loop;
  return v_plano_id;
end;
$$;

create or replace view public.tratamento_rastreabilidade
with (security_invoker=true)
as
select a.id as aplicacao_id,a.aplicada_em,a.paciente_id,a.paciente_nome_snapshot,
       a.plano_id,p.nome as plano_nome,a.tipo,a.sessao_numero,a.sessoes_total,
       a.profissional,a.status,a.observacoes,a.intercorrencias,
       ai.id as aplicacao_item_id,ai.ativo_nome,ai.dose,ai.unidade,ai.via,
       ai.lote_id,ai.lote_numero_snapshot,ai.validade_snapshot,
       ai.fabricante_snapshot,ai.origem_lote,a.criado_por,a.criado_em
from public.tratamento_aplicacoes a
join public.tratamento_aplicacao_itens ai on ai.aplicacao_id=a.id
left join public.tratamento_planos p on p.id=a.plano_id;

alter table public.tratamento_planos enable row level security;
alter table public.tratamento_plano_itens enable row level security;
alter table public.tratamento_aplicacoes enable row level security;
alter table public.tratamento_aplicacao_itens enable row level security;
alter table public.tratamento_auditoria enable row level security;

revoke all on public.tratamento_planos,public.tratamento_plano_itens,
  public.tratamento_aplicacoes,public.tratamento_aplicacao_itens,public.tratamento_auditoria from anon;
revoke insert,update,delete on public.tratamento_planos,public.tratamento_plano_itens,
  public.tratamento_aplicacoes,public.tratamento_aplicacao_itens,public.tratamento_auditoria from authenticated;
grant select on public.tratamento_planos,public.tratamento_plano_itens to authenticated;
grant select on public.tratamento_aplicacoes,public.tratamento_aplicacao_itens,public.tratamento_auditoria,public.tratamento_rastreabilidade to authenticated;
revoke all on function public.registrar_tratamento_aplicacao(uuid,uuid,text,integer,integer,timestamptz,text,text,text,uuid,jsonb) from public;
revoke all on function public.salvar_tratamento_plano(uuid,text,integer,date,text,text,text,uuid,uuid,jsonb) from public;
grant execute on function public.registrar_tratamento_aplicacao(uuid,uuid,text,integer,integer,timestamptz,text,text,text,uuid,jsonb) to authenticated;
grant execute on function public.salvar_tratamento_plano(uuid,text,integer,date,text,text,text,uuid,uuid,jsonb) to authenticated;

do $$
declare t text;
begin
  foreach t in array array['tratamento_planos','tratamento_plano_itens','tratamento_aplicacoes','tratamento_aplicacao_itens'] loop
    execute format('drop policy if exists %I on public.%I',t||'_select',t);
    execute format('create policy %I on public.%I for select to authenticated using (public.can_access_module(''precificador''))',t||'_select',t);
  end loop;
end $$;

drop policy if exists tratamento_planos_insert on public.tratamento_planos;
drop policy if exists tratamento_planos_update on public.tratamento_planos;
drop policy if exists tratamento_plano_itens_insert on public.tratamento_plano_itens;
drop policy if exists tratamento_plano_itens_update on public.tratamento_plano_itens;

drop policy if exists tratamento_auditoria_select on public.tratamento_auditoria;
create policy tratamento_auditoria_select on public.tratamento_auditoria for select to authenticated
using (public.can_access_module('precificador'));

commit;
