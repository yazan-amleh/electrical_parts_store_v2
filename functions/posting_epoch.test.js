'use strict';

const assert = require('node:assert/strict');
const {describe, it} = require('node:test');
const {
  SHARD_COUNT, VERSION, shardForEntry, epochsMatch, validateEpoch,
} = require('./accounting/posting_epoch');

class CheckpointError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

describe('sharded accounting posting change fence', () => {
  it('produces stable bounded shard numbers and rejects invalid IDs', () => {
    const a = shardForEntry('invoice-12-journal');
    assert.equal(a, shardForEntry('invoice-12-journal'));
    assert.equal(a >= 0 && a < SHARD_COUNT, true);
    assert.equal(Number.isInteger(a), true);
    assert.equal(VERSION, 1);
    assert.throws(() => shardForEntry('invalid/id'));
  });

  it('matches exactly sixteen versioned safe-integer sequence values', () => {
    const baseline = Array(SHARD_COUNT).fill(0);
    validateEpoch(baseline, CheckpointError);
    assert.equal(epochsMatch(baseline, [...baseline]), true);
    const changed = [...baseline];
    changed[shardForEntry('posted-id')] += 1;
    assert.equal(epochsMatch(baseline, changed), false);
    assert.equal(epochsMatch(baseline, baseline.slice(0, -1)), false);
  });

  it('rejects corrupt or unsafe persisted epoch counters', () => {
    for (const bad of [
      [],
      Array(SHARD_COUNT).fill(-1),
      Array(SHARD_COUNT).fill(1.5),
      Array(SHARD_COUNT).fill(Number.MAX_SAFE_INTEGER + 1),
      '0,0,0',
    ]) {
      assert.throws(() => validateEpoch(bad, CheckpointError),
        (e) => e.code === 'failed-precondition');
    }
  });
});
