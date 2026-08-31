import fs from 'node:fs';
import assert from 'node:assert/strict';

const admin=fs.readFileSync(new URL('../administracao.html',import.meta.url),'utf8');
const estoque=fs.readFileSync(new URL('../estoque.html',import.meta.url),'utf8');
const sql=fs.readFileSync(new URL('../supabase-usuarios-integridade.sql',import.meta.url),'utf8');
let total=0;

function test(nome,fn){
  total++;
  try{fn();console.log('PASS',nome);}
  catch(error){console.error('FAIL',nome);throw error;}
}

test('novas contas do Auth geram perfil automaticamente',()=>{
  assert.match(sql,/after insert on auth\.users/);
  assert.match(sql,/execute function public\.criar_perfil_para_usuario_auth/);
});
test('função do gatilho é security definer com search_path fixo',()=>{
  assert.match(sql,/security definer\s+set search_path = public, auth, pg_temp/);
});
test('nível do gatilho é seguro e não confia em metadata',()=>{
  assert.match(sql,/values \(new\.id,v_nome,lower\(new\.email\),'colaborador',true/);
  assert.doesNotMatch(sql,/raw_user_meta_data\s*->>\s*'nivel'/);
});
test('migração recupera contas invisíveis',()=>{
  assert.match(sql,/from auth\.users u/);
  assert.match(sql,/where not exists \(select 1 from public\.perfis p where p\.id=u\.id\)/);
});
test('migração não sobrescreve nem reativa perfis existentes',()=>{
  assert.match(sql,/on conflict \(id\) do nothing/g);
  assert.doesNotMatch(sql,/on conflict \(id\) do update/);
});
for(const [nome,html] of [['administração',admin],['estoque',estoque]]){
  test(`${nome} trava criação duplicada por clique`,()=>{
    assert.match(html,/CRIANDO_USUARIO/);
    assert.match(html,/botao\.disabled=true/);
    assert.match(html,/finally\s*\{/);
  });
  test(`${nome} envia JWT da sessão para a função`,()=>{
    const corpo=html.match(/async function criarUsuario\(\)[\s\S]*?\n\}/)?.[0]||'';
    assert.match(corpo,/session\.access_token/);
  });
  test(`${nome} persiste o perfil retornado pelo Auth`,()=>{
    const corpo=html.match(/async function criarUsuario\(\)[\s\S]*?\n\}/)?.[0]||'';
    assert.match(corpo,/from\('perfis'\)\.upsert/);
  });
  test(`${nome} trata respostas não JSON e erros estruturados`,()=>{
    assert.match(html,/resp\.text\(\)/);
    assert.match(html,/mensagemErroUsuario/);
  });
}

console.log(`\n${total}/${total} testes de integridade de usuários passaram.`);
