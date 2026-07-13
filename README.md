# Clínica Luisa Costa

Sistema web estático para gestão da clínica, publicado na Vercel e integrado ao Supabase.

## Módulos

- `index.html`: login, dashboard e navegação principal.
- `agenda.html`: agenda e confirmações.
- `pacientes.html`: carteira, histórico e relacionamento.
- `precificador.html`: preços, protocolos e sessões.
- `estoque.html`: medicamentos, lotes, fornecedores e movimentações.
- `financeiro.html`: lançamentos, inadimplência e DRE.
- `administracao.html`: usuários, permissões e configurações.
- `cadastro.html`: cadastro público de pacientes.

## Banco de dados

Execute os arquivos no SQL Editor do Supabase nesta ordem:

1. `supabase-administracao.sql`
2. `supabase-agenda.sql`
3. `supabase-precificador-cadastro.sql`
4. `supabase-protocolos-idempotencia.sql` (proteção contra protocolos duplicados)
5. `supabase-cadastro-publico-rpc.sql`
6. `supabase-cadastro-publico-fix.sql`
7. `supabase-pacientes-policies.sql`
8. `supabase-operacional-policies.sql`
9. `supabase-financeiro-paciente-id.sql`
10. `supabase-seguranca-rls.sql` — último arquivo de políticas
11. `supabase-financeiro-quitacao.sql` — quitação financeira transacional
12. `supabase-financeiro-integridade.sql` — pagamentos vinculados, saldo por protocolo e idempotência

O arquivo de segurança remove políticas antigas permissivas e aplica autorização por módulo. Usuários sem perfil ativo não recebem acesso. As funções transacionais podem ser instaladas depois dele.

O cadastro público usa exclusivamente a função `criar_paciente_publico(jsonb)`. O `INSERT` anônimo direto em `pacientes` permanece revogado.

## Estrutura operacional ainda não versionada

As tabelas financeiras e de estoque já usadas no ambiente de produção não têm sua criação completa neste repositório. Para exportá-las com fidelidade, execute `supabase-inventario-schema.sql` no SQL Editor e salve o resultado antes de tentar recriar essas estruturas.

## Desenvolvimento local

```sh
python3 -m http.server 8765
```

Abra `http://localhost:8765`. Não abra os HTMLs diretamente por `file://`, pois os módulos são carregados por `fetch` dentro do dashboard.
