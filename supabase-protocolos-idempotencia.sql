-- Clínica Luisa Costa — idempotência na criação de protocolos.
-- Migração aditiva: registros históricos permanecem inalterados.

alter table public.protocolos
  add column if not exists idempotency_key uuid;

create unique index if not exists protocolos_idempotency_key_uidx
  on public.protocolos(idempotency_key)
  where idempotency_key is not null;

comment on column public.protocolos.idempotency_key is
  'Identifica uma tentativa de criação e impede protocolos duplicados por reenvio.';
