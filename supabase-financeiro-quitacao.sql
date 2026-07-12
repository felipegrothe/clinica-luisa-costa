-- Clínica Luisa Costa — quitação financeira atômica.
-- Execute após supabase-seguranca-rls.sql.

create or replace function public.registrar_quitacao_financeira(
  p_origem text,
  p_registro_id text,
  p_valor numeric,
  p_data date,
  p_forma text,
  p_paciente text,
  p_paciente_id uuid,
  p_descricao text,
  p_observacao text default null
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_total numeric;
  v_pago numeric;
  v_saldo numeric;
  v_novo_pago numeric;
  v_novo_saldo numeric;
  v_lancamento_id uuid;
begin
  if not public.can_access_module('financeiro') then
    raise exception 'Acesso financeiro negado';
  end if;
  if p_valor is null or p_valor <= 0 then
    raise exception 'Valor de quitação inválido';
  end if;
  if p_data is null then
    raise exception 'Data de quitação obrigatória';
  end if;
  if p_origem not in ('manual','protocolo') then
    raise exception 'Origem de quitação inválida';
  end if;

  if p_origem = 'manual' then
    select valor_total, valor_pago, saldo_devedor
      into v_total, v_pago, v_saldo
    from public.fin_inadimplentes
    where id = p_registro_id::uuid
    for update;

    if not found then raise exception 'Conta a receber não encontrada'; end if;
    if p_valor > v_saldo + 0.009 then raise exception 'Pagamento superior ao saldo'; end if;

    v_novo_pago := coalesce(v_pago,0) + p_valor;
    v_novo_saldo := greatest(0,coalesce(v_total,0)-v_novo_pago);

    update public.fin_inadimplentes
      set valor_pago=v_novo_pago,
          saldo_devedor=v_novo_saldo,
          quitado=v_novo_saldo < 0.01
    where id=p_registro_id::uuid;
  end if;

  insert into public.fin_lancamentos(
    tipo,descricao,categoria_dre,valor,data,forma_pagamento,paciente,
    paciente_id,obs,pago,user_id
  ) values (
    'receita','Quitação — '||coalesce(nullif(trim(p_paciente),''),'Paciente'),
    '1.4',p_valor,p_data,coalesce(nullif(p_forma,''),'pix'),
    nullif(trim(p_paciente),''),p_paciente_id,
    concat_ws(' | ',nullif(trim(p_observacao),''),'Ref: '||coalesce(p_descricao,'—')),
    coalesce(nullif(p_forma,''),'pix') <> 'boleto',auth.uid()
  ) returning id into v_lancamento_id;

  return jsonb_build_object(
    'lancamento_id',v_lancamento_id,
    'saldo_devedor',case when p_origem='manual' then v_novo_saldo else null end
  );
end;
$$;

revoke all on function public.registrar_quitacao_financeira(text,text,numeric,date,text,text,uuid,text,text) from public;
grant execute on function public.registrar_quitacao_financeira(text,text,numeric,date,text,text,uuid,text,text) to authenticated;
