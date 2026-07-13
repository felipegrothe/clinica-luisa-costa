import fs from 'node:fs';
import assert from 'node:assert/strict';

const html=fs.readFileSync(new URL('../estoque.html',import.meta.url),'utf8');
const sql=fs.readFileSync(new URL('../supabase-estoque-integridade.sql',import.meta.url),'utf8');
const schema=fs.readFileSync(new URL('../supabase-estoque-schema.sql',import.meta.url),'utf8');
let total=0;

function test(nome,fn){
  total++;
  try{fn();console.log('PASS',nome);}
  catch(error){console.error('FAIL',nome);throw error;}
}

test('colaborador recebe acesso explícito ao módulo',()=>{
  assert.match(sql,/values \('colaborador','estoque',true\)/);
});
test('colaborador não integra o perfil de manutenção',()=>{
  const corpo=sql.match(/function public\.estoque_can_manage\(\)[\s\S]*?\$\$;/)?.[0]||'';
  assert.doesNotMatch(corpo,/'colaborador'/);
});
test('colaborador pode retirar somente quando possui acesso ao módulo',()=>{
  assert.match(sql,/can_access_module\('estoque'\)[\s\S]*?'colaborador'/);
});
test('política ampla FOR ALL é removida',()=>{
  assert.match(sql,/drop policy if exists %I[\s\S]*?_module_access/);
  assert.doesNotMatch(sql,/create policy[^;]+for all to authenticated[^;]+can_access_module\('estoque'\)/i);
});
test('movimentações não aceitam escrita direta autenticada',()=>{
  assert.match(sql,/revoke insert, update, delete on public\.movimentacoes from authenticated/);
  assert.match(sql,/revoke insert, update, delete on public\.tirzepatida_movimentacoes from authenticated/);
});
test('retirada é uma RPC security definer',()=>{
  assert.match(sql,/function public\.estoque_retirar\([\s\S]*?security definer/);
});
test('retirada exige motivo',()=>assert.match(sql,/Informe o motivo ou paciente da retirada/));
test('retirada exige chave de idempotência',()=>assert.match(sql,/Chave de idempotência obrigatória/));
test('retirada serializa chamadas da mesma chave',()=>assert.match(sql,/pg_advisory_xact_lock/));
test('retirada de medicamento usa somente lotes aprovados',()=>{
  const corpo=sql.match(/function public\.estoque_retirar\([\s\S]*?revoke all on function public\.estoque_retirar/)?.[0]||'';
  assert.match(corpo,/status='aprovado'/);
  assert.doesNotMatch(corpo,/rejeitado.*descartado/);
});
test('lotes são consumidos por validade com bloqueio',()=>{
  assert.match(sql,/order by validade nulls last, criado_em, id[\s\S]*?for update/);
});
test('saldo e movimentação são persistidos na mesma função',()=>{
  assert.match(sql,/update public\.lotes[\s\S]*?insert into public\.movimentacoes/);
});
test('ajustes usam RPC atômica',()=>assert.match(html,/rpc\('estoque_ajustar_quantidade'/));
test('tela não grava movimentações diretamente',()=>{
  assert.doesNotMatch(html,/from\('movimentacoes'\)\.insert/);
  assert.doesNotMatch(html,/from\('tirzepatida_movimentacoes'\)\.insert/);
});
test('tela não atualiza lote diretamente durante retirada',()=>assert.doesNotMatch(html,/lotesFonte/));
test('botão de retirada possui trava contra clique duplo',()=>{
  assert.match(html,/RETIRADA_EM_ANDAMENTO/);
  assert.match(html,/btn\.disabled=true/);
  assert.match(html,/finally\s*\{/);
});
test('cadastros possuem trava comum contra clique duplo',()=>{
  assert.match(html,/var ESTOQUE_SALVANDO = \{\}/);
  for(const chave of ['lote','tirz','med','impl','ins'])assert.match(html,new RegExp(`iniciarSalvamento\\('${chave}'`));
});
test('uma tentativa reaproveita a mesma chave idempotente',()=>{
  assert.match(html,/pendRet=\{[^\n]+chave:novaChaveOperacao\(\)/);
  assert.match(html,/p_chave_idempotencia:retSnapshot\.chave/);
});
test('cadastro de medicamento e lote inicial é transacional',()=>{
  assert.match(html,/rpc\('estoque_criar_medicamento'/);
  assert.match(sql,/function public\.estoque_criar_medicamento/);
});
test('entrada de lote é transacional',()=>assert.match(html,/rpc\('estoque_registrar_lote'/));
test('aprovação e auditoria são atômicas',()=>assert.match(html,/rpc\('estoque_decidir_lote'/));
test('aprovação possui trava contra repetição simultânea',()=>{
  assert.match(html,/LOTE_PROCESSANDO/);
  assert.match(html,/finally\{LOTE_PROCESSANDO=false;\}/);
});
test('tirzepatida e implantes usam cadastro transacional',()=>assert.match(html,/rpc\('estoque_criar_frasco'/));
test('insumo e fornecedor usam cadastro transacional',()=>assert.match(html,/rpc\('estoque_criar_insumo'/));
test('data operacional usa calendário local',()=>{
  assert.match(html,/function dateLocal\(/);
  assert.doesNotMatch(html,/function today\(\)\{ return new Date\(\)\.toISOString/);
});
test('valor remanescente é proporcional ao saldo',()=>{
  assert.match(html,/preco_pago\)\*Math\.max\(0,Math\.min\(total,disp\)\)\/total/);
});
test('respostas da IA são inseridas como texto',()=>{
  assert.match(html,/bubble\.textContent=String\(text\|\|''\)/);
  assert.doesNotMatch(html,/text\.replace\(\/\\n\/g,'<br>'\)/);
});
test('criação de usuário envia token da sessão, não chave pública',()=>{
  const corpo=html.match(/async function criarUsuario\(\)[\s\S]*?\/\/ ── PDF RETIRADA/)?.[0]||'';
  assert.match(corpo,/session\.access_token/);
  assert.doesNotMatch(corpo,/Authorization':'Bearer '\+SUPA_KEY/);
});
test('navegação principal usa botões e semântica de tabs',()=>{
  assert.match(html,/<button class="ntab on"[^>]+role="tab"/);
  assert.match(html,/role="tablist"/);
});
test('interface possui adaptação para tablet e celular',()=>{
  assert.match(html,/@media \(max-width:900px\)/);
  assert.match(html,/@media \(max-width:520px\)/);
});
test('campos recebem associação automática com labels',()=>assert.match(html,/label\.htmlFor=field\.id/));
test('colaborador não vê controles de manutenção',()=>{
  assert.match(html,/document\.querySelectorAll\('\.manage-only'\)/);
  assert.match(html,/isManager\(\)\?'<button[^']+Adicionar/);
});
test('alias admin é reconhecido pela interface',()=>assert.match(html,/nivelAtual\(\)==='administrador'\|\|nivelAtual\(\)==='admin'/));
test('acesso direto ao estoque valida permissão do módulo',()=>{
  const corpo=html.match(/async function iniciarApp\(user\)[\s\S]*?async function fazerLogout/)?.[0]||'';
  assert.match(corpo,/permissoes_modulos/);
  assert.match(corpo,/modulo','estoque/);
});
test('schema operacional do estoque está versionado',()=>{
  for(const tabela of ['itens','lotes','movimentacoes','tirzepatida_frascos','tirzepatida_movimentacoes','fornecedores','setores','auditoria'])
    assert.match(schema,new RegExp(`create table if not exists public\\.${tabela}`));
  for(const view of ['estoque_atual','alertas_validade','comparativo_fornecedores','dashboard'])
    assert.match(schema,new RegExp(`create or replace view public\\.${view}`));
});

console.log(`\n${total}/${total} testes de estoque passaram.`);
