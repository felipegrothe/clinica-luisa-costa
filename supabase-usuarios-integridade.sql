-- Clínica Luisa Costa — integridade entre Supabase Auth e perfis da aplicação.
-- Execute depois de supabase-administracao.sql e supabase-seguranca-rls.sql.
-- Idempotente: pode ser executado novamente com segurança.

begin;

create or replace function public.criar_perfil_para_usuario_auth()
returns trigger
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_nome text;
begin
  v_nome := nullif(btrim(coalesce(
    new.raw_user_meta_data ->> 'nome',
    new.raw_user_meta_data ->> 'name',
    new.raw_user_meta_data ->> 'full_name',
    split_part(coalesce(new.email,''),'@',1)
  )), '');

  insert into public.perfis (id,nome,email,nivel,ativo,criado_em,atualizado_em)
  values (new.id,v_nome,lower(new.email),'colaborador',true,coalesce(new.created_at,now()),now())
  on conflict (id) do nothing;

  return new;
end
$$;

drop trigger if exists auth_usuario_criar_perfil on auth.users;
create trigger auth_usuario_criar_perfil
after insert on auth.users
for each row execute function public.criar_perfil_para_usuario_auth();

-- Recupera contas que já existem no Auth, mas ficaram invisíveis porque o
-- perfil não foi persistido. Não altera perfis existentes nem reativa contas.
insert into public.perfis (id,nome,email,nivel,ativo,criado_em,atualizado_em)
select
  u.id,
  nullif(btrim(coalesce(
    u.raw_user_meta_data ->> 'nome',
    u.raw_user_meta_data ->> 'name',
    u.raw_user_meta_data ->> 'full_name',
    split_part(coalesce(u.email,''),'@',1)
  )), ''),
  lower(u.email),
  'colaborador',
  true,
  coalesce(u.created_at,now()),
  now()
from auth.users u
where not exists (select 1 from public.perfis p where p.id=u.id)
on conflict (id) do nothing;

commit;
