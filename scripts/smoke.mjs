import assert from 'node:assert/strict';
const [base, expectedCommit] = process.argv.slice(2);
assert.ok(base && expectedCommit, 'Uso: node scripts/smoke.mjs URL COMMIT');
let lastError;
for (let attempt = 1; attempt <= 18; attempt++) {
  try {
    const response = await fetch(`${base.replace(/\/$/, '')}/health`, { signal: AbortSignal.timeout(10000) });
    assert.equal(response.status, 200);
    const data = await response.json();
    assert.equal(data.status, 'ok');
    assert.equal(data.commit, expectedCommit, 'A revisão publicada não corresponde ao commit aprovado');
    console.log(`SMOKE OK: HTTP 200, status ok, commit ${expectedCommit}`);
    process.exit(0);
  } catch (error) {
    lastError = error;
    if (attempt < 18) await new Promise(resolve => setTimeout(resolve, 10000));
  }
}
throw lastError;
