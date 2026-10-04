// Local smoke checks; does not substitute for live PostgreSQL policy tests.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(__dirname+'/portal.js','utf8');
class Element{constructor(){this.innerHTML='';this.textContent='';this.hidden=false;this.disabled=false;this.open=false;this.handlers={};}addEventListener(k,v){this.handlers[k]=v;}showModal(){this.open=true;}close(){this.open=false;this.handlers.close?.();}querySelector(){return new Element();}querySelectorAll(){return [];}setAttribute(){}click(){} }
const elements=new Map();const el=id=>{if(!elements.has(id))elements.set(id,new Element());return elements.get(id);};
const records={rm_residents:[{id:'r1',title:'DEMO Resident',status:'Active',details:{phase:'Orientation'},created_at:'2026-10-01',updated_at:'2026-10-01',is_demo:true}],rm_tasks:[],rm_goals:[],rm_appointments:[],rm_announcements:[],rm_charges:[],rm_payments:[]};
const fakeDB={from(name){const response={data:records[name]||[],error:null,count:(records[name]||[]).length};const query={select(){return query},order(){return query},limit(){return query},eq(){return query},then(resolve){return Promise.resolve(response).then(resolve)}};return query;}};
const context={document:{getElementById:el,querySelector:()=>new Element(),querySelectorAll:()=>[],addEventListener(){}},window:{},console,setTimeout:()=>1,clearTimeout(){},Date,Intl,FormData,URL,Blob,crypto:require('node:crypto').webcrypto,location:{origin:'https://tofhouston.org',pathname:'/results-matter/',hash:''},history:{replaceState(){}},confirm:()=>false,prompt:()=>null};
vm.createContext(context);vm.runInContext(source,context);
assert.match(el('content').innerHTML,/Portal unavailable/);
assert.equal(vm.runInContext("esc('<img src=x onerror=alert(1)>')",context),'&lt;img src=x onerror=alert(1)&gt;');
vm.runInContext("authView()",context);assert.match(el('content').innerHTML,/Sign in/);assert.match(el('content').innerHTML,/Request account/);
vm.runInContext("profile={role:'Resident',display_name:'DEMO Resident'}; user={id:'u1'}; rights={residents:{can_view:true},goals:{can_view:true,can_create:true},tasks:{can_view:true},appointments:{can_view:true},documents:{can_view:true},requests:{can_view:true,can_create:true},charges:{can_view:true},payments:{can_view:true},messages:{can_view:true},resources:{can_view:true}}; shell()",context);
assert.match(el('content').innerHTML,/My Goals/);assert.match(el('content').innerHTML,/My Profile/);assert.doesNotMatch(el('content').innerHTML,/data-nav="admin"|data-nav="incidents"|data-nav="cases"/);
context.fakeDB=fakeDB;
(async()=>{
 await vm.runInContext("db=fakeDB; dashboard(document.getElementById('workspace'))",context);
 assert.match(el('workspace').innerHTML,/Welcome, DEMO Resident/);assert.match(el('workspace').innerHTML,/Orientation/);
 vm.runInContext("profile={role:'Super Administrator',display_name:'Admin'}; rights=Object.fromEntries(Object.keys(DEFINITIONS).map(k=>[k,{can_view:true,can_create:true,can_edit:true,can_export:true,can_delete:true}])); shell()",context);
 assert.match(el('content').innerHTML,/data-nav="admin"/);assert.match(el('content').innerHTML,/Case Management/);
 assert.match(el('content').innerHTML,/global-search-form/);
 await vm.runInContext("selectedResident={id:'r1',title:'DEMO Resident',status:'Active',details:{phase:'Orientation'},created_at:'2026-10-01'};residentWorkspace(document.getElementById('workspace'))",context);
 assert.match(el('workspace').innerHTML,/Case management/);assert.match(el('workspace').innerHTML,/Financial ledger/);
 vm.runInContext("profile={role:'Resident',display_name:'DEMO Resident'};rights={residents:{can_view:true},goals:{can_view:true},tasks:{can_view:true},documents:{can_view:true}}",context);
 await vm.runInContext("residentWorkspace(document.getElementById('workspace'))",context);
 assert.doesNotMatch(el('workspace').innerHTML,/profile-case|profile-transition|profile-ledger/);
 await vm.runInContext("globalSearch('DEMO')",context);
 assert.match(el('workspace').innerHTML,/DEMO Resident/);assert.doesNotMatch(el('workspace').innerHTML,/Case notes/);
 vm.runInContext("selectedResident=null;profile={role:'Super Administrator'};rights=Object.fromEntries(Object.keys(DEFINITIONS).map(k=>[k,{can_view:true,can_create:true,can_edit:true,can_export:true,can_delete:true}]))",context);
 await vm.runInContext("moduleView(document.getElementById('workspace'),'tasks')",context);assert.match(el('records').innerHTML,/No matching records/);
 vm.runInContext("rows=[{id:'x',title:'<script>bad()</script>',status:'Not Started',created_at:'2026-10-01',details:{}}];paintRows('tasks')",context);assert.doesNotMatch(el('records').innerHTML,/<script>/);assert.match(el('records').innerHTML,/&lt;script&gt;/);
 vm.runInContext("applicationView()",context);assert.match(el('content').innerHTML,/consent/);assert.match(el('content').innerHTML,/Electronic signature/);
 const sql=fs.readFileSync(__dirname+'/setup.sql','utf8');assert.ok(sql.startsWith('-- Results Matter'));assert.match(sql,/revoke all on public\.rm_profiles/);assert.match(sql,/Request decisions are staff-only/);assert.match(sql,/where resident_visible/);assert.match(sql,/last_seen>now\(\)-interval '20 minutes'/);assert.match(sql,/a\.details-'review_notes'/);assert.doesNotMatch(sql,/using\(true\).*rm_residents/);
 console.log('PASS: syntax load, login surface, role navigation, database-fed dashboard, empty state, escaped records, public application, and policy source guards.');
 console.log('NOT RUN: browser geometry or live PostgreSQL/RLS/integration checks.');
})().catch(e=>{console.error(e);process.exitCode=1;});
