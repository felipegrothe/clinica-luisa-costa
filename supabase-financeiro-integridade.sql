-- Clínica Luisa Costa — núcleo de integridade financeira (etapa 1).
-- Migração aditiva e idempotente. Não altera pagamentos históricos.
-- Execute após supabase-seguranca-rls.sql.

create table if not exists public.fin_pagamentos (
  id uuid primary key default gen_random_uuid(),
  idempotency_key uuid not null,
  origem text not null check (origem in ('manual','protocolo')),
  conta_receber_id uuid references public.fin_inadimplentes(id) on delete restrict,
  protocolo_id uuid references public.protocolos(id) on delete restrict,
  lancamento_id uuid references public.fin_lancamentos(id) on delete restrict,
  valor numeric(14,2) not null check (valor > 0),
  data_pagamento date not null,
  forma_pagamento text not null,
  paciente_id uuid,
  observacao text,
  user_id uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  constraint fin_pagamentos_origem_vinculo_check check (
    (origem='manual' and conta_receber_id is not null and protocolo_id is null)
    or (origem='protocolo' and protocolo_id is not null and conta_receber_id is null)
  )
);

create unique index if not exists fin_pagamentos_idempotency_uidx
  on public.fin_pagamentos(idempotency_key);
create index if not exists fin_pagamentos_conta_idx
  on public.fin_pagamentos(conta_receber_id);
create index if not exists fin_pagamentos_protocolo_idx
  on public.fin_pagamentos(protocolo_id);
create index if not exists fin_pagamentos_lancamento_idx
  on public.fin_pagamentos(lancamento_id);

alter table public.fin_pagamentos enable row level security;
grant select, insert on public.fin_pagamentos to authenticated;
drop policy if exists "fin_pagamentos_module_access" on public.fin_pagamentos;
create policy "fin_pagamentos_module_access"
  on public.fin_pagamentos for all to authenticated
  using (public.can_access_module('financeiro'))
  with check (public.can_access_module('financeiro') and user_id=auth.uid());

drop function if exists public.registrar_quitacao_financeira(text,text,numeric,date,text,text,uuid,text,text);

create or replace function public.registrar_quitacao_financeira(
  p_origem text,
  p_registro_id text,
  p_valor numeric,
  p_data date,
  p_forma text,
  p_paciente text,
  p_paciente_id uuid,
  p_descricao text,
  p_observacao text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_total numeric(14,2);
  v_pago numeric(14,2);
  v_saldo numeric(14,2);
  v_novo_pago numeric(14,2);
  v_novo_saldo numeric(14,2);
  v_lancamento_id uuid;
  v_pagamento_id uuid;
  v_existente public.fin_pagamentos%rowtype;
begin
  if not public.can_access_module('financeiro') then
    raise exception 'Acesso financeiro negado';
  end if;
  if p_idempotency_key is null then
    raise exception 'Chave de idempotência obrigatória';
  end if;
  if p_valor is null or round(p_valor,2) <= 0 then
    raise exception 'Valor de quitação inválido';
  end if;
  if p_valor <> round(p_valor,2) then
    raise exception 'Valor deve possuir no máximo duas casas decimais';
  end if;
  if p_data is null then
    raise exception 'Data de quitação obrigatória';
  end if;
  if p_origem not in ('manual','protocolo') then
    raise exception 'Origem de quitação inválida';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text,0));
  select * into v_existente
  from public.fin_pagamentos
  where idempotency_key=p_idempotency_key;
  if found then
    return jsonb_build_object(
      'pagamento_id',v_existente.id,
      'lancamento_id',v_existente.lancamento_id,
      'duplicado',true
    );
  end if;

  if p_origem='manual' then
    select valor_total,valor_pago,saldo_devedor
      into v_total,v_pago,v_saldo
    from public.fin_inadimplentes
    where id=p_registro_id::uuid
    for update;
    if not found then raise exception 'Conta a receber não encontrada'; end if;
    v_pago := coalesce(v_pago,0);
    v_saldo := greatest(0,coalesce(v_total,0)-v_pago);
  else
    select valor_total into v_total
    from public.protocolos
    where id=p_registro_id::uuid and status='andamento'
    for update;
    if not found then raise exception 'Protocolo ativo não encontrado'; end if;
    select coalesce(sum(valor),0) into v_pago
    from public.fin_pagamentos
    where protocolo_id=p_registro_id::uuid;
    v_saldo := greatest(0,coalesce(v_total,0)-v_pago);
  end if;

  if round(p_valor,2) > v_saldo then
    raise exception 'Pagamento superior ao saldo';
  end if;
  v_novo_pago := v_pago+round(p_valor,2);
  v_novo_saldo := greatest(0,v_total-v_novo_pago);

  insert into public.fin_lancamentos(
    tipo,descricao,categoria_dre,valor,data,forma_pagamento,paciente,
    paciente_id,obs,pago,user_id
  ) values (
    'receita','Quitação — '||coalesce(nullif(trim(p_paciente),''),'Paciente'),
    '1.4',round(p_valor,2),p_data,coalesce(nullif(p_forma,''),'pix'),
    nullif(trim(p_paciente),''),p_paciente_id,
    concat_ws(' | ',nullif(trim(p_observacao),''),'Ref: '||coalesce(p_descricao,'—')),
    true,auth.uid()
  ) returning id into v_lancamento_id;

  insert into public.fin_pagamentos(
    idempotency_key,origem,conta_receber_id,protocolo_id,lancamento_id,
    valor,data_pagamento,forma_pagamento,paciente_id,observacao,user_id
  ) values (
    p_idempotency_key,p_origem,
    case when p_origem='manual' then p_registro_id::uuid end,
    case when p_origem='protocolo' then p_registro_id::uuid end,
    v_lancamento_id,round(p_valor,2),p_data,
    coalesce(nullif(p_forma,''),'pix'),p_paciente_id,p_observacao,auth.uid()
  ) returning id into v_pagamento_id;

  if p_origem='manual' then
    update public.fin_inadimplentes
      set valor_pago=v_novo_pago,
          saldo_devedor=v_novo_saldo,
          quitado=v_novo_saldo < 0.01
    where id=p_registro_id::uuid;
  end if;

  return jsonb_build_object(
    'pagamento_id',v_pagamento_id,
    'lancamento_id',v_lancamento_id,
    'saldo_devedor',v_novo_saldo,
    'duplicado',false
  );
end;
$$;

revoke all on function public.registrar_quitacao_financeira(text,text,numeric,date,text,text,uuid,text,text,uuid) from public;
grant execute on function public.registrar_quitacao_financeira(text,text,numeric,date,text,text,uuid,text,text,uuid) to authenticated;
