-- Clinica Luisa Costa
-- Funcao segura para cadastro publico de pacientes.
-- Use quando o INSERT direto em pacientes continuar bloqueado por RLS.

create or replace function public.criar_paciente_publico(payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  novo_id uuid;
  nome_normalizado text := trim(coalesce(payload->>'nome',''));
  telefone_normalizado text := regexp_replace(coalesce(payload->>'telefone',''), '\\D', '', 'g');
begin
  if char_length(nome_normalizado) < 3 or char_length(nome_normalizado) > 160 then
    raise exception 'Nome inválido';
  end if;
  if char_length(telefone_normalizado) < 10 or char_length(telefone_normalizado) > 11 then
    raise exception 'Telefone inválido';
  end if;
  if octet_length(convert_to(payload::text,'UTF8')) > 20000 then
    raise exception 'Cadastro excede o tamanho permitido';
  end if;

  insert into public.pacientes (
    nome,
    cpf,
    telefone,
    email,
    nascimento,
    genero,
    estado_civil,
    profissao,
    altura,
    peso_inicial,
    hobbies,
    medicamentos,
    cep,
    logradouro,
    numero,
    complemento,
    bairro,
    cidade,
    estado,
    origem,
    origem_indicador_nome,
    objetivos,
    foto_url,
    cadastro_origem,
    status,
    relacionamento,
    consultas,
    protocolos
  )
  values (
    nome_normalizado,
    nullif(payload->>'cpf',''),
    nullif(payload->>'telefone',''),
    nullif(payload->>'email',''),
    nullif(payload->>'nascimento','')::date,
    nullif(payload->>'genero',''),
    nullif(payload->>'estado_civil',''),
    nullif(payload->>'profissao',''),
    nullif(payload->>'altura','')::numeric,
    nullif(payload->>'peso_inicial','')::numeric,
    nullif(payload->>'hobbies',''),
    nullif(payload->>'medicamentos',''),
    nullif(payload->>'cep',''),
    nullif(payload->>'logradouro',''),
    nullif(payload->>'numero',''),
    nullif(payload->>'complemento',''),
    nullif(payload->>'bairro',''),
    nullif(payload->>'cidade',''),
    nullif(payload->>'estado',''),
    nullif(payload->>'origem',''),
    nullif(payload->>'origem_indicador_nome',''),
    coalesce(array(select jsonb_array_elements_text(payload->'objetivos')), array[]::text[]),
    null,
    'publico',
    'aguardando_revisao',
    coalesce(payload->'relacionamento','{}'::jsonb),
    '[]'::jsonb,
    '[]'::jsonb
  )
  returning id into novo_id;

  return novo_id;
end;
$$;

revoke all on function public.criar_paciente_publico(jsonb) from public;
grant execute on function public.criar_paciente_publico(jsonb) to anon, authenticated;

notify pgrst, 'reload schema';
