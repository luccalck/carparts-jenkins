import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

export function metrics(csv) {
  const lines = csv.trim().split(/\r?\n/);
  const header = lines.shift().split(',');
  const expected = ['build', 'commit', 'commit_at', 'build_started', 'build_finished', 'deployed_at', 'build_result', 'change_failed'];
  assert.deepEqual(header, expected, 'Cabeçalho CSV inválido');
  const runs = lines.filter(Boolean).map(line => {
    const values = line.split(',');
    assert.equal(values.length, header.length, 'Não use vírgulas dentro dos campos');
    return Object.fromEntries(header.map((key, i) => [key, values[i]]));
  });
  assert.ok(runs.length >= 10, `Exigem-se 10 execuções reais; encontradas ${runs.length}`);
  assert.equal(new Set(runs.map(r => r.build)).size, runs.length, 'Build duplicado');
  const date = text => { const value = Date.parse(text); assert.ok(Number.isFinite(value), `Data inválida: ${text}`); return value; };
  for (const r of runs) {
    assert.ok(['SUCCESS', 'FAILURE', 'ABORTED'].includes(r.build_result));
    assert.ok(['true', 'false', ''].includes(r.change_failed));
    assert.ok(date(r.build_finished) >= date(r.build_started));
    assert.ok(date(r.build_started) >= date(r.commit_at));
    if (r.deployed_at) {
      assert.ok(date(r.deployed_at) >= date(r.commit_at));
      assert.ok(['true', 'false'].includes(r.change_failed), 'Classifique incidentes de cada implantação');
    } else assert.equal(r.change_failed, '', 'Sem deploy, não conte falha de mudança');
  }
  const deployed = runs.filter(r => r.deployed_at);
  assert.ok(deployed.length, 'Nenhuma implantação real registrada');
  const times = deployed.map(r => (date(r.deployed_at) - date(r.commit_at)) / 86400000).sort((a, b) => a - b);
  const middle = Math.floor(times.length / 2);
  const median = times.length % 2 ? times[middle] : (times[middle - 1] + times[middle]) / 2;
  const observationStart = Math.min(...runs.map(r => date(r.build_started)));
  const observationEnd = Math.max(...runs.map(r => Math.max(date(r.build_finished), r.deployed_at ? date(r.deployed_at) : 0)));
  const days = (observationEnd - observationStart) / 86400000;
  assert.ok(days > 0, 'Janela de observação sem duração');
  return {
    executions: runs.length, deployments: deployed.length,
    observation_days: days, lead_time_median_days: median,
    baseline_days: 11, target_days: 2,
    reduction_percent: (11 - median) / 11 * 100,
    deployments_per_day: deployed.length / days,
    change_failure_percent: deployed.filter(r => r.change_failed === 'true').length / deployed.length * 100,
    warning: 'Amostra de laboratório não comprova a meta da equipe durante dois meses.'
  };
}
if (process.argv[1]?.endsWith('metrics.mjs')) {
  try { console.log(JSON.stringify(metrics(readFileSync(process.argv[2] || 'metrics/runs.csv', 'utf8')), null, 2)); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
