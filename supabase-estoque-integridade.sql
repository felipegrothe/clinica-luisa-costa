-- Clínica Luisa Costa — segurança e integridade transacional do estoque.
-- Execute depois de supabase-seguranca-rls.sql.
-- Idempotente: pode ser executado novamente sem duplicar políticas ou operações.

begin;

create or replace function public.estoque_can_manage()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    public.can_access_module('estoque')
    and public.current_user_level() in ('admin','administrador','compras'),
    false
  )
$$;

create or replace function public.estoque_can_withdraw()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    public.can_access_module('estoque')
    and public.current_user_level() in ('admin','administrador','compras','colaborador'),
    false
  )
$$;

grant execute on function public.estoque_can_manage() to authenticated;
grant execute on function public.estoque_can_withdraw() to authenticated;

-- O colaborador clínico consulta o estoque e registra retiradas exclusivamente
-- pelas funções transacionais abaixo. Ele não recebe escrita direta nas tabelas.
insert into public.permissoes_modulos (nivel, modulo, pode_acessar)
values ('colaborador','estoque',true)
on conflict (nivel, modulo) do update
set pode_acessar=excluded.pode_acessar, updated_at=now();

create table if not exists public.estoque_operacoes_idempotentes (
  usuario_id uuid not null,
  chave uuid not null,
  operacao text not null,
  resultado jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now(),
  primary key (usuario_id, chave)
);

alter table public.estoque_operacoes_idempotentes enable row level security;
revoke all on public.estoque_operacoes_idempotentes from anon, authenticated;

-- Remove a política ampla FOR ALL criada pelo endurecimento genérico e aplica
-- capacidades separadas. Views são configuradas como security_invoker quando
-- suportado, para respeitarem a RLS das tabelas subjacentes.
do $$
declare
  t text;
begin
  foreach t in array array[
    'itens','lotes','movimentacoes','tirzepatida_frascos',
    'tirzepatida_movimentacoes','fornecedores','setores','auditoria'
  ] loop
    if to_regclass('public.'||t) is not null then
      execute format('alter table public.%I enable row level security',t);
      execute format('drop policy if exists %I on public.%I',t||'_module_access',t);
      execute format('drop policy if exists %I on public.%I',t||'_estoque_select',t);
      execute format('drop policy if exists %I on public.%I',t||'_estoque_insert',t);
      execute format('drop policy if exists %I on public.%I',t||'_estoque_update',t);
      execute format('drop policy if exists %I on public.%I',t||'_estoque_delete',t);
    end if;
  end loop;

  if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='estoque_atual' and c.relkind='v') then
    execute 'alter view public.estoque_atual set (security_invoker=true)';
  end if;
  if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='dashboard' and c.relkind='v') then
    execute 'alter view public.dashboard set (security_invoker=true)';
  end if;
  if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='alertas_validade' and c.relkind='v') then
    execute 'alter view public.alertas_validade set (security_invoker=true)';
  end if;
  if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='comparativo_fornecedores' and c.relkind='v') then
    execute 'alter view public.comparativo_fornecedores set (security_invoker=true)';
  end if;
end $$;

-- Catálogo e saldos: leitura para quem acessa o módulo; manutenção para
-- administrador/compras. Exclusão lógica continua exclusiva do administrador.
create policy "itens_estoque_select" on public.itens
for select to authenticated using (public.can_access_module('estoque'));
create policy "itens_estoque_insert" on public.itens
for insert to authenticated with check (public.estoque_can_manage());
create policy "itens_estoque_update" on public.itens
for update to authenticated using (public.estoque_can_manage()) with check (public.estoque_can_manage());
create policy "itens_estoque_delete" on public.itens
for delete to authenticated using (public.is_admin());

create policy "lotes_estoque_select" on public.lotes
for select to authenticated using (public.can_access_module('estoque'));
create policy "lotes_estoque_insert" on public.lotes
for insert to authenticated with check (public.estoque_can_manage());
create policy "lotes_estoque_update" on public.lotes
for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "lotes_estoque_delete" on public.lotes
for delete to authenticated using (public.is_admin());

create policy "tirzepatida_frascos_estoque_select" on public.tirzepatida_frascos
for select to authenticated using (public.can_access_module('estoque'));
create policy "tirzepatida_frascos_estoque_insert" on public.tirzepatida_frascos
for insert to authenticated with check (public.estoque_can_manage());
create policy "tirzepatida_frascos_estoque_update" on public.tirzepatida_frascos
for update to authenticated using (public.estoque_can_manage()) with check (public.estoque_can_manage());
create policy "tirzepatida_frascos_estoque_delete" on public.tirzepatida_frascos
for delete to authenticated using (public.is_admin());

create policy "fornecedores_estoque_select" on public.fornecedores
for select to authenticated using (public.can_access_module('estoque'));
create policy "fornecedores_estoque_insert" on public.fornecedores
for insert to authenticated with check (public.estoque_can_manage());
create policy "fornecedores_estoque_update" on public.fornecedores
for update to authenticated using (public.estoque_can_manage()) with check (public.estoque_can_manage());
create policy "fornecedores_estoque_delete" on public.fornecedores
for delete to authenticated using (public.is_admin());

create policy "setores_estoque_select" on public.setores
for select to authenticated using (public.can_access_module('estoque'));
create policy "setores_estoque_insert" on public.setores
for insert to authenticated with check (public.is_admin());
create policy "setores_estoque_update" on public.setores
for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "setores_estoque_delete" on public.setores
for delete to authenticated using (public.is_admin());

-- Movimentações e auditoria são append-only e só podem ser gravadas pelas RPCs.
create policy "movimentacoes_estoque_select" on public.movimentacoes
for select to authenticated using (public.can_access_module('estoque'));
create policy "tirzepatida_movimentacoes_estoque_select" on public.tirzepatida_movimentacoes
for select to authenticated using (public.can_access_module('estoque'));
create policy "auditoria_estoque_select" on public.auditoria
for select to authenticated using (public.is_admin());
create policy "auditoria_estoque_insert" on public.auditoria
for insert to authenticated with check (public.estoque_can_manage() and usuario_id=auth.uid());

revoke insert, update, delete on public.movimentacoes from authenticated;
revoke insert, update, delete on public.tirzepatida_movimentacoes from authenticated;
grant insert on public.auditoria to authenticated;
revoke update, delete on public.auditoria from authenticated;

-- Retirada FEFO, atômica e idempotente. Qualquer erro reverte saldo,
-- movimentação e auditoria na mesma transação.
create or replace function public.estoque_retirar(
  p_tipo text,
  p_registro_id uuid,
  p_quantidade integer,
  p_data date,
  p_motivo text,
  p_chave_idempotencia uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existente jsonb;
  v_resultado jsonb;
  v_restante numeric;
  v_disponivel numeric;
  v_total numeric;
  v_usado numeric;
  v_desconto numeric;
  v_nome text;
  v_usuario_nome text;
  l record;
begin
  if not public.estoque_can_withdraw() then
    raise exception 'Acesso negado para retirada de estoque' using errcode='42501';
  end if;
  if p_tipo not in ('med','tirz','impl','ins') then
    raise exception 'Tipo de estoque inválido';
  end if;
  if coalesce(p_quantidade,0) <= 0 then
    raise exception 'A quantidade deve ser maior que zero';
  end if;
  if p_data is null then
    raise exception 'Informe a data da retirada';
  end if;
  if nullif(btrim(p_motivo),'') is null then
    raise exception 'Informe o motivo ou paciente da retirada';
  end if;
  if p_chave_idempotencia is null then
    raise exception 'Chave de idempotência obrigatória';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':'||p_chave_idempotencia::text,0));
  select resultado into v_existente
  from public.estoque_operacoes_idempotentes
  where usuario_id=auth.uid() and chave=p_chave_idempotencia;
  if found then return v_existente; end if;

  select coalesce(nome,email,auth.uid()::text) into v_usuario_nome
  from public.perfis where id=auth.uid();

  if p_tipo='med' then
    select nome into v_nome from public.itens where id=p_registro_id and ativo is true for update;
    if not found then raise exception 'Medicamento não encontrado ou inativo'; end if;
    v_restante:=p_quantidade;
    select coalesce(sum(greatest(0,coalesce(quantidade_cx,0)*coalesce(amp_por_caixa,1)-coalesce(usado_base,0))),0)
      into v_disponivel
    from public.lotes where item_id=p_registro_id and status='aprovado';
    if v_disponivel < p_quantidade then raise exception 'Saldo aprovado insuficiente'; end if;

    for l in
      select id,coalesce(usado_base,0) usado_base,
             greatest(0,coalesce(quantidade_cx,0)*coalesce(amp_por_caixa,1)-coalesce(usado_base,0)) saldo
      from public.lotes
      where item_id=p_registro_id and status='aprovado'
      order by validade nulls last, criado_em, id
      for update
    loop
      exit when v_restante<=0;
      v_desconto:=least(v_restante,l.saldo);
      if v_desconto>0 then
        update public.lotes set usado_base=l.usado_base+v_desconto where id=l.id;
        v_restante:=v_restante-v_desconto;
      end if;
    end loop;

    insert into public.movimentacoes(item_id,tipo,quantidade,data,motivo,responsavel_id,responsavel_nome)
    values(p_registro_id,'saida',p_quantidade,p_data,btrim(p_motivo),auth.uid(),v_usuario_nome);

  elsif p_tipo in ('tirz','impl') then
    select coalesce(ampolas_total,0),coalesce(ampolas_usadas,0),
           coalesce(nullif(observacoes,''),case when p_tipo='tirz' then 'Tirzepatida' else 'Implante' end)
      into v_total,v_usado,v_nome
    from public.tirzepatida_frascos
    where id=p_registro_id and status='ativo'
      and ((p_tipo='tirz' and coalesce(mg,0)<>0) or (p_tipo='impl' and coalesce(mg,0)=0))
    for update;
    if not found then raise exception 'Frasco ou lote não encontrado'; end if;
    if greatest(0,v_total-v_usado)<p_quantidade then raise exception 'Saldo insuficiente'; end if;

    update public.tirzepatida_frascos
    set ampolas_usadas=v_usado+p_quantidade, atualizado_em=now()
    where id=p_registro_id;
    insert into public.tirzepatida_movimentacoes(frasco_id,tipo,quantidade,data,motivo,responsavel_id,responsavel_nome)
    values(p_registro_id,'saida',p_quantidade,p_data,btrim(p_motivo),auth.uid(),v_usuario_nome);

  else
    select coalesce(nome,'Item'),coalesce(estoque_ideal,0),coalesce(usado_total,0)
      into v_nome,v_total,v_usado
    from public.itens where id=p_registro_id and ativo is true for update;
    if not found then raise exception 'Item não encontrado ou inativo'; end if;
    if greatest(0,v_total-v_usado)<p_quantidade then raise exception 'Saldo insuficiente'; end if;
    update public.itens set usado_total=v_usado+p_quantidade, atualizado_em=now() where id=p_registro_id;
    insert into public.movimentacoes(item_id,tipo,quantidade,data,motivo,responsavel_id,responsavel_nome)
    values(p_registro_id,'saida',p_quantidade,p_data,btrim(p_motivo),auth.uid(),v_usuario_nome);
  end if;

  insert into public.auditoria(usuario_id,usuario_nome,acao,tabela,dados_depois)
  values(auth.uid(),v_usuario_nome,'retirada','movimentacoes',jsonb_build_object(
    'item',v_nome,'tipo',p_tipo,'quantidade',p_quantidade,'data',p_data,'motivo',btrim(p_motivo)
  ));

  v_resultado:=jsonb_build_object('ok',true,'item',v_nome,'tipo',p_tipo,'quantidade',p_quantidade,'data',p_data);
  insert into public.estoque_operacoes_idempotentes(usuario_id,chave,operacao,resultado)
  values(auth.uid(),p_chave_idempotencia,'retirada',v_resultado);
  return v_resultado;
end
$$;

revoke all on function public.estoque_retirar(text,uuid,integer,date,text,uuid) from public, anon;
grant execute on function public.estoque_retirar(text,uuid,integer,date,text,uuid) to authenticated;

-- Ajustes manuais são atômicos e exclusivos de administrador/compras.
create or replace function public.estoque_ajustar_quantidade(
  p_tipo text,
  p_registro_id uuid,
  p_delta integer,
  p_motivo text,
  p_chave_idempotencia uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existente jsonb;
  v_resultado jsonb;
  v_total numeric;
  v_usado numeric;
  v_novo numeric;
  v_nome text;
  v_usuario_nome text;
begin
  if not public.estoque_can_manage() then raise exception 'Acesso negado' using errcode='42501'; end if;
  if p_tipo not in ('tirz','impl','ins') then raise exception 'Tipo inválido'; end if;
  if coalesce(p_delta,0)=0 then raise exception 'O ajuste não pode ser zero'; end if;
  if nullif(btrim(p_motivo),'') is null then raise exception 'Informe o motivo do ajuste'; end if;
  if p_chave_idempotencia is null then raise exception 'Chave de idempotência obrigatória'; end if;

  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':'||p_chave_idempotencia::text,0));
  select resultado into v_existente from public.estoque_operacoes_idempotentes
   where usuario_id=auth.uid() and chave=p_chave_idempotencia;
  if found then return v_existente; end if;
  select coalesce(nome,email,auth.uid()::text) into v_usuario_nome from public.perfis where id=auth.uid();

  if p_tipo in ('tirz','impl') then
    select coalesce(ampolas_total,0),coalesce(ampolas_usadas,0),
           coalesce(nullif(observacoes,''),case when p_tipo='tirz' then 'Tirzepatida' else 'Implante' end)
      into v_total,v_usado,v_nome
    from public.tirzepatida_frascos where id=p_registro_id and status='ativo' for update;
    if not found then raise exception 'Registro não encontrado'; end if;
    v_novo:=v_total+p_delta;
    if v_novo<0 or v_novo<v_usado then raise exception 'O ajuste excede o saldo disponível'; end if;
    update public.tirzepatida_frascos set ampolas_total=v_novo,atualizado_em=now() where id=p_registro_id;
  else
    select coalesce(nome,'Item'),coalesce(estoque_ideal,0),coalesce(usado_total,0)
      into v_nome,v_total,v_usado from public.itens where id=p_registro_id and ativo is true for update;
    if not found then raise exception 'Item não encontrado'; end if;
    -- delta positivo adiciona estoque; delta negativo baixa estoque.
    v_novo:=greatest(0,v_usado-p_delta);
    if p_delta<0 and v_usado-p_delta>v_total then raise exception 'O ajuste excede o saldo disponível'; end if;
    update public.itens set usado_total=v_novo,atualizado_em=now() where id=p_registro_id;
  end if;

  insert into public.auditoria(usuario_id,usuario_nome,acao,tabela,dados_depois)
  values(auth.uid(),v_usuario_nome,'ajuste_estoque','estoque',jsonb_build_object(
    'item',v_nome,'tipo',p_tipo,'delta',p_delta,'motivo',btrim(p_motivo)
  ));
  v_resultado:=jsonb_build_object('ok',true,'item',v_nome,'tipo',p_tipo,'delta',p_delta);
  insert into public.estoque_operacoes_idempotentes(usuario_id,chave,operacao,resultado)
  values(auth.uid(),p_chave_idempotencia,'ajuste',v_resultado);
  return v_resultado;
end
$$;

revoke all on function public.estoque_ajustar_quantidade(text,uuid,integer,text,uuid) from public, anon;
grant execute on function public.estoque_ajustar_quantidade(text,uuid,integer,text,uuid) to authenticated;

-- Cadastro do medicamento e do lote inicial na mesma transação.
create or replace function public.estoque_criar_medicamento(
  p_nome text,
  p_unidade text,
  p_amp_por_caixa integer,
  p_estoque_min integer,
  p_estoque_ideal integer,
  p_setor_id uuid,
  p_fornecedor_nome text default null,
  p_quantidade_cx integer default 0,
  p_validade date default null,
  p_preco_total numeric default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item_id uuid;
  v_fornecedor_id uuid;
  v_status text;
  v_usuario_nome text;
begin
  if not public.estoque_can_manage() then raise exception 'Acesso negado' using errcode='42501'; end if;
  if nullif(btrim(p_nome),'') is null then raise exception 'Informe o nome do medicamento'; end if;
  if coalesce(p_amp_por_caixa,0)<=0 then raise exception 'Unidades por embalagem deve ser maior que zero'; end if;
  if coalesce(p_estoque_min,0)<0 or coalesce(p_estoque_ideal,0)<0 then raise exception 'Estoques mínimo e ideal não podem ser negativos'; end if;
  if p_setor_id is null then raise exception 'Informe o setor'; end if;
  if coalesce(p_quantidade_cx,0)>0 and p_validade is null then raise exception 'Informe a validade do lote inicial'; end if;
  if exists(select 1 from public.itens where ativo is true and setor_id=p_setor_id and lower(btrim(nome))=lower(btrim(p_nome))) then
    raise exception 'Já existe um item ativo com este nome no setor';
  end if;

  if nullif(btrim(p_fornecedor_nome),'') is not null then
    select id into v_fornecedor_id from public.fornecedores where lower(btrim(nome))=lower(btrim(p_fornecedor_nome)) order by id limit 1;
    if not found then
      insert into public.fornecedores(nome,tipo) values(btrim(p_fornecedor_nome),'farmacia') returning id into v_fornecedor_id;
    end if;
  end if;

  insert into public.itens(nome,unidade,amp_por_caixa,estoque_min,estoque_ideal,setor_id,ativo)
  values(btrim(p_nome),coalesce(nullif(btrim(p_unidade),''),'caixas'),p_amp_por_caixa,
         coalesce(p_estoque_min,0),coalesce(p_estoque_ideal,0),p_setor_id,true)
  returning id into v_item_id;

  if coalesce(p_quantidade_cx,0)>0 then
    v_status:=case when public.is_admin() then 'aprovado' else 'pendente' end;
    insert into public.lotes(item_id,validade,quantidade_cx,amp_por_caixa,preco_total,fornecedor_id,status,
                             aprovado_por,aprovado_em,criado_por)
    values(v_item_id,p_validade,p_quantidade_cx,p_amp_por_caixa,coalesce(p_preco_total,0),v_fornecedor_id,v_status,
           case when public.is_admin() then auth.uid() else null end,
           case when public.is_admin() then now() else null end,auth.uid());
  end if;

  select coalesce(nome,email,auth.uid()::text) into v_usuario_nome from public.perfis where id=auth.uid();
  insert into public.auditoria(usuario_id,usuario_nome,acao,tabela,registro_id,dados_depois)
  values(auth.uid(),v_usuario_nome,'criou_medicamento','itens',v_item_id,
         jsonb_build_object('nome',btrim(p_nome),'quantidade_cx',coalesce(p_quantidade_cx,0)));
  return jsonb_build_object('ok',true,'item_id',v_item_id,'lote_status',v_status);
end
$$;

revoke all on function public.estoque_criar_medicamento(text,text,integer,integer,integer,uuid,text,integer,date,numeric) from public, anon;
grant execute on function public.estoque_criar_medicamento(text,text,integer,integer,integer,uuid,text,integer,date,numeric) to authenticated;

-- Entrada de lote com fornecedor e auditoria atômicos.
create or replace function public.estoque_registrar_lote(
  p_item_id uuid,
  p_numero_lote text,
  p_validade date,
  p_quantidade_cx integer,
  p_amp_por_caixa integer,
  p_preco_total numeric,
  p_fornecedor_nome text,
  p_observacoes text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fornecedor_id uuid;
  v_lote_id uuid;
  v_status text;
  v_item_nome text;
  v_usuario_nome text;
begin
  if not public.estoque_can_manage() then raise exception 'Acesso negado' using errcode='42501'; end if;
  if p_validade is null then raise exception 'Informe a validade'; end if;
  if coalesce(p_quantidade_cx,0)<=0 or coalesce(p_amp_por_caixa,0)<=0 then raise exception 'Quantidade inválida'; end if;
  select nome into v_item_nome from public.itens where id=p_item_id and ativo is true;
  if not found then raise exception 'Item não encontrado ou inativo'; end if;
  if nullif(btrim(p_fornecedor_nome),'') is not null then
    select id into v_fornecedor_id from public.fornecedores where lower(btrim(nome))=lower(btrim(p_fornecedor_nome)) order by id limit 1;
    if not found then insert into public.fornecedores(nome,tipo) values(btrim(p_fornecedor_nome),'farmacia') returning id into v_fornecedor_id; end if;
  end if;
  v_status:=case when public.is_admin() then 'aprovado' else 'pendente' end;
  insert into public.lotes(item_id,numero_lote,validade,quantidade_cx,amp_por_caixa,preco_total,fornecedor_id,
                           observacoes,status,aprovado_em,aprovado_por,criado_por)
  values(p_item_id,nullif(btrim(p_numero_lote),''),p_validade,p_quantidade_cx,p_amp_por_caixa,
         coalesce(p_preco_total,0),v_fornecedor_id,nullif(btrim(p_observacoes),''),v_status,
         case when public.is_admin() then now() else null end,
         case when public.is_admin() then auth.uid() else null end,auth.uid())
  returning id into v_lote_id;
  select coalesce(nome,email,auth.uid()::text) into v_usuario_nome from public.perfis where id=auth.uid();
  insert into public.auditoria(usuario_id,usuario_nome,acao,tabela,registro_id,dados_depois)
  values(auth.uid(),v_usuario_nome,'criou_lote','lotes',v_lote_id,
         jsonb_build_object('item',v_item_nome,'quantidade_cx',p_quantidade_cx,'validade',p_validade,'status',v_status));
  return jsonb_build_object('ok',true,'lote_id',v_lote_id,'status',v_status);
end
$$;

revoke all on function public.estoque_registrar_lote(uuid,text,date,integer,integer,numeric,text,text) from public, anon;
grant execute on function public.estoque_registrar_lote(uuid,text,date,integer,integer,numeric,text,text) to authenticated;

create or replace function public.estoque_criar_insumo(
  p_nome text,
  p_setor_id uuid,
  p_unidade text,
  p_estoque_min integer,
  p_estoque_ideal integer,
  p_preco_unitario numeric,
  p_fornecedor_nome text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item_id uuid;
  v_fornecedor_id uuid;
  v_usuario_nome text;
begin
  if not public.estoque_can_manage() then raise exception 'Acesso negado' using errcode='42501'; end if;
  if nullif(btrim(p_nome),'') is null or p_setor_id is null then raise exception 'Nome e setor são obrigatórios'; end if;
  if coalesce(p_estoque_min,0)<0 or coalesce(p_estoque_ideal,0)<0 then raise exception 'Saldos não podem ser negativos'; end if;
  if exists(select 1 from public.itens where ativo is true and setor_id=p_setor_id and lower(btrim(nome))=lower(btrim(p_nome))) then
    raise exception 'Já existe um item ativo com este nome no setor';
  end if;
  if nullif(btrim(p_fornecedor_nome),'') is not null then
    select id into v_fornecedor_id from public.fornecedores where lower(btrim(nome))=lower(btrim(p_fornecedor_nome)) order by id limit 1;
    if not found then insert into public.fornecedores(nome,tipo) values(btrim(p_fornecedor_nome),'outro') returning id into v_fornecedor_id; end if;
  end if;
  insert into public.itens(nome,setor_id,unidade,estoque_min,estoque_ideal,amp_por_caixa,ativo,preco_unitario,fornecedor_id)
  values(btrim(p_nome),p_setor_id,coalesce(nullif(btrim(p_unidade),''),'un'),coalesce(p_estoque_min,0),
         coalesce(p_estoque_ideal,0),1,true,coalesce(p_preco_unitario,0),v_fornecedor_id)
  returning id into v_item_id;
  select coalesce(nome,email,auth.uid()::text) into v_usuario_nome from public.perfis where id=auth.uid();
  insert into public.auditoria(usuario_id,usuario_nome,acao,tabela,registro_id,dados_depois)
  values(auth.uid(),v_usuario_nome,'criou_insumo','itens',v_item_id,jsonb_build_object('nome',btrim(p_nome)));
  return jsonb_build_object('ok',true,'item_id',v_item_id);
end
$$;

revoke all on function public.estoque_criar_insumo(text,uuid,text,integer,integer,numeric,text) from public, anon;
grant execute on function public.estoque_criar_insumo(text,uuid,text,integer,integer,numeric,text) to authenticated;

create or replace function public.estoque_decidir_lote(p_lote_id uuid,p_decisao text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_usuario_nome text;
begin
  if not public.is_admin() then raise exception 'Apenas administradores podem decidir lotes' using errcode='42501'; end if;
  if p_decisao not in ('aprovar','rejeitar') then raise exception 'Decisão inválida'; end if;
  v_status:=case when p_decisao='aprovar' then 'aprovado' else 'rejeitado' end;
  update public.lotes
  set status=v_status,
      aprovado_por=case when p_decisao='aprovar' then auth.uid() else null end,
      aprovado_em=case when p_decisao='aprovar' then now() else null end
  where id=p_lote_id and status='pendente';
  if not found then raise exception 'Lote pendente não encontrado ou já processado'; end if;
  select coalesce(nome,email,auth.uid()::text) into v_usuario_nome from public.perfis where id=auth.uid();
  insert into public.auditoria(usuario_id,usuario_nome,acao,tabela,registro_id,dados_depois)
  values(auth.uid(),v_usuario_nome,case when p_decisao='aprovar' then 'aprovou_lote' else 'rejeitou_lote' end,
         'lotes',p_lote_id,jsonb_build_object('status',v_status));
  return jsonb_build_object('ok',true,'lote_id',p_lote_id,'status',v_status);
end
$$;

revoke all on function public.estoque_decidir_lote(uuid,text) from public, anon;
grant execute on function public.estoque_decidir_lote(uuid,text) to authenticated;

create or replace function public.estoque_criar_frasco(
  p_tipo text,
  p_mg integer,
  p_fornecedor_nome text,
  p_numero_lote text,
  p_validade date,
  p_quantidade integer,
  p_preco_pago numeric,
  p_observacoes text,
  p_estoque_min integer,
  p_estoque_ideal integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_fornecedor_id uuid;
  v_usuario_nome text;
begin
  if not public.estoque_can_manage() then raise exception 'Acesso negado' using errcode='42501'; end if;
  if p_tipo not in ('tirz','impl') then raise exception 'Tipo inválido'; end if;
  if p_validade is null or coalesce(p_quantidade,0)<=0 then raise exception 'Validade e quantidade são obrigatórias'; end if;
  if p_tipo='tirz' and nullif(btrim(p_fornecedor_nome),'') is null then raise exception 'Informe o fornecedor'; end if;
  if p_tipo='impl' and nullif(btrim(p_observacoes),'') is null then raise exception 'Informe o nome do implante'; end if;
  if nullif(btrim(p_fornecedor_nome),'') is not null then
    select id into v_fornecedor_id from public.fornecedores where lower(btrim(nome))=lower(btrim(p_fornecedor_nome)) order by id limit 1;
    if not found then insert into public.fornecedores(nome,tipo) values(btrim(p_fornecedor_nome),'farmacia') returning id into v_fornecedor_id; end if;
  end if;
  insert into public.tirzepatida_frascos(
    mg,fornecedor_id,numero_lote,validade,ampolas_total,ampolas_usadas,preco_pago,observacoes,
    estoque_min_ampolas,estoque_ideal_ampolas,criado_por,status
  ) values(
    case when p_tipo='impl' then 0 else p_mg end,v_fornecedor_id,nullif(btrim(p_numero_lote),''),p_validade,
    p_quantidade,0,coalesce(p_preco_pago,0),nullif(btrim(p_observacoes),''),coalesce(p_estoque_min,0),
    coalesce(p_estoque_ideal,0),auth.uid(),'ativo'
  ) returning id into v_id;
  select coalesce(nome,email,auth.uid()::text) into v_usuario_nome from public.perfis where id=auth.uid();
  insert into public.auditoria(usuario_id,usuario_nome,acao,tabela,registro_id,dados_depois)
  values(auth.uid(),v_usuario_nome,'criou_'||case when p_tipo='impl' then 'implante' else 'tirzepatida' end,
         'tirzepatida_frascos',v_id,jsonb_build_object('tipo',p_tipo,'quantidade',p_quantidade,'validade',p_validade));
  return jsonb_build_object('ok',true,'id',v_id,'tipo',p_tipo);
end
$$;

revoke all on function public.estoque_criar_frasco(text,integer,text,text,date,integer,numeric,text,integer,integer) from public, anon;
grant execute on function public.estoque_criar_frasco(text,integer,text,text,date,integer,numeric,text,integer,integer) to authenticated;

-- Garante que aliases históricos de administrador sejam tratados igualmente.
update public.permissoes_modulos p
set pode_acessar=a.pode_acessar, updated_at=now()
from public.permissoes_modulos a
where a.nivel='administrador' and p.nivel='admin' and p.modulo=a.modulo;

commit;
