import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { metrics } from '../scripts/metrics.mjs';
const header = 'build,commit,commit_at,build_started,build_finished,deployed_at,build_result,change_failed';
// Fixtures unitárias, não representam execuções reais de Jenkins.
const fixture = Array.from({ length: 10 }, (_, i) => `${i + 1},fixture-${i},2026-01-01T00:00:00Z,2026-01-01T01:00:00Z,2026-01-01T02:00:00Z,2026-01-02T00:00:00Z,SUCCESS,${i === 0}`);
describe('Validação das métricas', () => {
test('métricas têm denominador de implantações e mediana de um dia', () => {
  const result = metrics([header, ...fixture].join('\n'));
  assert.equal(result.executions, 10);
  assert.equal(result.lead_time_median_days, 1);
  assert.equal(result.change_failure_percent, 10);
});
test('métricas recusam menos de dez execuções', () => {
  assert.throws(() => metrics([header, ...fixture.slice(0, 9)].join('\n')), /10 execuções/);
});
test('métricas recusam build duplicado', () => {
  assert.throws(() => metrics([header, ...fixture, fixture[0]].join('\n')), /duplicado/);
});
});
