-- Clínica Luisa Costa — estornos, conciliação e auditoria financeira.
-- Migração aditiva e idempotente. Não altera lançamentos históricos.

alter table public.fin_lancamentos
  add column if not exists estornado_at timestamptz,
  add column if not exists estornado_por uuid,
  add column if not exists estorno_motivo text,
  add column if not exists conciliado_at timestamptz,
  add column if not exists conciliado_por uuid,
  add column if not exists conciliacao_ref text;

alter table public.fin_pagamentos
  add column if not exists estornado_at timestamptz,
  add column if not exists estornado_por uuid;

create table if not exists public.fin_estornos (
  id uuid primary key default gen_random_uuid(),
  idempotency_key uuid not null unique,
  lancamento_id uuid not null references public.fin_lancamentos(id) on delete restrict,
  pagamento_id uuid references public.fin_pagamentos(id) on delete restrict,
  motivo text not null,
  user_id uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  constraint fin_estornos_lancamento_uidx unique(lancamento_id)
);

create table if not exists public.fin_auditoria (
  id uuid primary key default gen_random_uuid(),
  entidade text not null,
  entidade_id uuid not null,
  acao text not null,
  dados_antes jsonb,
  dados_depois jsonb,
  motivo text,
  user_id uuid not null default auth.uid(),
  created_at timestamptz not null default now()
);

create index if not exists fin_auditoria_entidade_idx
  on public.fin_auditoria(entidade,entidade_id,created_at desc);

alter table public.fin_estornos enable row level security;
alter table public.fin_auditoria enable row level security;
grant select, insert on public.fin_estornos to authenticated;
grant select, insert on public.fin_auditoria to authenticated;

drop policy if exists "fin_estornos_module_access" on public.fin_estornos;
create policy "fin_estornos_module_access" on public.fin_estornos
  for all to authenticated
  using (public.can_access_module('financeiro'))
  with check (public.can_access_module('financeiro') and user_id=auth.uid());

drop policy if exists "fin_auditoria_module_access" on public.fin_auditoria;
create policy "fin_auditoria_module_access" on public.fin_auditoria
  for all to authenticated
  using (public.can_access_module('financeiro'))
  with check (public.can_access_module('financeiro') and user_id=auth.uid());

create or replace function public.estornar_lancamento_financeiro(
  p_lancamento_id uuid,
  p_motivo text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security invoker
set search_path=public
as $$
declare
  v_lanc public.fin_lancamentos%rowtype;
  v_pag public.fin_pagamentos%rowtype;
  v_estorno public.fin_estornos%rowtype;
  v_total numeric(14,2);
  v_pago numeric(14,2);
  v_novo_pago numeric(14,2);
begin
  if not public.can_access_module('financeiro') then
    raise exception 'Acesso financeiro negado';
  end if;
  if p_lancamento_id is null or p_idempotency_key is null then
    raise exception 'Lançamento e chave de idempotência são obrigatórios';
  end if;
  if length(trim(coalesce(p_motivo,''))) < 5 then
    raise exception 'Informe um motivo de estorno com pelo menos 5 caracteres';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text,0));
  select * into v_estorno from public.fin_estornos
    where idempotency_key=p_idempotency_key;
  if found then
    return jsonb_build_object('estorno_id',v_estorno.id,'duplicado',true);
  end if;

  select * into v_lanc from public.fin_lancamentos
    where id=p_lancamento_id for update;
  if not found then raise exception 'Lançamento não encontrado'; end if;
  if v_lanc.estornado_at is not null then raise exception 'Lançamento já estornado'; end if;

  select * into v_pag from public.fin_pagamentos
    where lancamento_id=p_lancamento_id and estornado_at is null
    for update;

  if found then
    update public.fin_pagamentos
      set estornado_at=now(),estornado_por=auth.uid()
      where id=v_pag.id;

    if v_pag.origem='manual' then
      select valor_total,coalesce(valor_pago,0)
        into v_total,v_pago
      from public.fin_inadimplentes
      where id=v_pag.conta_receber_id for update;
      if found then
        v_novo_pago:=greatest(0,v_pago-v_pag.valor);
        update public.fin_inadimplentes
          set valor_pago=v_novo_pago,
              saldo_devedor=greatest(0,v_total-v_novo_pago),
              quitado=false
          where id=v_pag.conta_receber_id;
      end if;
    end if;
  end if;

  update public.fin_lancamentos
    set estornado_at=now(),estornado_por=auth.uid(),
        estorno_motivo=trim(p_motivo),conciliado_at=null,
        conciliado_por=null,conciliacao_ref=null
    where id=p_lancamento_id;

  insert into public.fin_estornos(
    idempotency_key,lancamento_id,pagamento_id,motivo,user_id
  ) values (
    p_idempotency_key,p_lancamento_id,v_pag.id,trim(p_motivo),auth.uid()
  ) returning * into v_estorno;

  insert into public.fin_auditoria(
    entidade,entidade_id,acao,dados_antes,dados_depois,motivo,user_id
  ) values (
    'fin_lancamentos',p_lancamento_id,'estorno',to_jsonb(v_lanc),
    jsonb_build_object('estornado_at',now(),'pagamento_id',v_pag.id),
    trim(p_motivo),auth.uid()
  );

  return jsonb_build_object(
    'estorno_id',v_estorno.id,'pagamento_id',v_pag.id,'duplicado',false
  );
end;
$$;

create or replace function public.conciliar_lancamento_financeiro(
  p_lancamento_id uuid,
  p_conciliado boolean,
  p_referencia text default null
)
returns jsonb
language plpgsql
security invoker
set search_path=public
as $$
declare
  v_antes public.fin_lancamentos%rowtype;
  v_depois public.fin_lancamentos%rowtype;
begin
  if not public.can_access_module('financeiro') then
    raise exception 'Acesso financeiro negado';
  end if;
  select * into v_antes from public.fin_lancamentos
    where id=p_lancamento_id for update;
  if not found then raise exception 'Lançamento não encontrado'; end if;
  if v_antes.estornado_at is not null then
    raise exception 'Lançamento estornado não pode ser conciliado';
  end if;
  if p_conciliado and length(trim(coalesce(p_referencia,''))) < 3 then
    raise exception 'Informe uma referência de conciliação';
  end if;

  update public.fin_lancamentos set
    conciliado_at=case when p_conciliado then now() else null end,
    conciliado_por=case when p_conciliado then auth.uid() else null end,
    conciliacao_ref=case when p_conciliado then trim(p_referencia) else null end
  where id=p_lancamento_id returning * into v_depois;

  insert into public.fin_auditoria(
    entidade,entidade_id,acao,dados_antes,dados_depois,motivo,user_id
  ) values (
    'fin_lancamentos',p_lancamento_id,
    case when p_conciliado then 'conciliacao' else 'desconciliacao' end,
    to_jsonb(v_antes),to_jsonb(v_depois),nullif(trim(p_referencia),''),auth.uid()
  );

  return jsonb_build_object(
    'lancamento_id',p_lancamento_id,'conciliado',p_conciliado,
    'conciliado_at',v_depois.conciliado_at
  );
end;
$$;

revoke all on function public.estornar_lancamento_financeiro(uuid,text,uuid) from public;
revoke all on function public.conciliar_lancamento_financeiro(uuid,boolean,text) from public;
grant execute on function public.estornar_lancamento_financeiro(uuid,text,uuid) to authenticated;
grant execute on function public.conciliar_lancamento_financeiro(uuid,boolean,text) to authenticated;
