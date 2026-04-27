alter table public.fin_lancamentos
  add column if not exists paciente_id uuid references public.pacientes(id) on delete set null;

create index if not exists fin_lancamentos_paciente_idx
  on public.fin_lancamentos(paciente_id);
