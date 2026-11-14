const assert = require('node:assert/strict');
const fs = require('node:fs');
const Module = require('node:module');
const ts = require('typescript');
let owner = false;
let calls = [];
const mock = {
  auth: { getUser: async () => ({ data: { user: { id: 'club-admin-account' } }, error: null }) },
  from(table) {
    calls.push(table);
    const result = () => ({ error: null, data: table === 'pfd_platform_owners' ? owner ? { user_id: 'owner-account' } : null : table === 'pfd_club_admins' ? [{ club_id: 'assigned-club' }] : table === 'pfd_clubs' ? [{ id: 'assigned-club', name: 'Assigned club' }, { id: 'other-club', name: 'Other club' }] : [{ permission_key: 'teams.view', enabled: true }] });
    const builder = { select() { return this; }, eq() { return this; }, order() { return this; }, abortSignal() { return this; }, maybeSingle() { return Promise.resolve(result()); }, then(resolve, reject) { return Promise.resolve(result()).then(resolve, reject); } };
    return builder;
  },
};
const filename = process.cwd() + '/lib/club-shell.ts';
const compiled = new Module(filename, module);
compiled.filename = filename;
compiled.paths = module.paths;
const originalRequire = compiled.require.bind(compiled);
compiled.require = id => id === './supabase' ? { getSupabase: () => mock } : originalRequire(id);
compiled._compile(ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, filename);
(async () => {
  const result = await compiled.exports.loadClubShell();
  assert.deepEqual(result.clubs.map(c => c.id), ['assigned-club']);
  assert.equal(result.permissions['teams.view'], true);
  assert.equal('isOwner' in result, false);
  owner = true; calls = [];
  await assert.rejects(compiled.exports.loadClubShell(), /separate Club Administrator account/);
  assert.deepEqual(calls, ['pfd_platform_owners'], 'Owner must be rejected before club queries');
  assert(!fs.readFileSync('app/account/owner-dashboard.tsx', 'utf8').includes('Open Club Admin view'));
  console.log('PASS: assigned clubs only; Owner account rejected before club reads; Owner preview link removed. SDK responses mocked.');
})().catch(e => { console.error(e); process.exitCode = 1; });
