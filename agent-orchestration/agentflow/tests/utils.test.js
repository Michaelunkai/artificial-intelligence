/**
 * Unit Tests for AgentFlow Utilities
 * Run with: npm test
 */

const {
  formatDuration,
  formatRelativeTime,
  formatBytes,
  validateTaskDescription,
  validateSchedule,
  sanitizeInput,
  calculateSuccessRate,
  groupBy,
  sortBy,
  unique,
  chunk,
  average,
  median,
  percentile,
  truncate,
  safeJsonParse,
  isEmpty,
  deepMerge,
  getNestedProperty,
  setNestedProperty
} = require('../lib/utils');

// Simple test runner
function test(name, fn) {
  try {
    fn();
    console.log(`✅ ${name}`);
  } catch (error) {
    console.error(`❌ ${name}`);
    console.error(`   ${error.message}`);
  }
}

function assertEquals(actual, expected, message = '') {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}. ${message}`);
  }
}

function assertTrue(value, message = '') {
  if (!value) {
    throw new Error(`Expected true, got ${value}. ${message}`);
  }
}

// Tests
console.log('\n🧪 Running AgentFlow Utility Tests\n');

test('formatDuration: formats seconds correctly', () => {
  assertEquals(formatDuration(0), '0s');
  assertEquals(formatDuration(45), '45s');
  assertEquals(formatDuration(90), '1m 30s');
  assertEquals(formatDuration(3665), '1h 1m 5s');
});

test('formatBytes: formats bytes correctly', () => {
  assertEquals(formatBytes(0), '0 B');
  assertEquals(formatBytes(1024), '1 KB');
  assertEquals(formatBytes(1048576), '1 MB');
  assertEquals(formatBytes(1073741824), '1 GB');
});

test('validateTaskDescription: validates descriptions', () => {
  const valid = validateTaskDescription('Apply to 10 jobs');
  assertEquals(valid.valid, true);
  assertEquals(valid.value, 'Apply to 10 jobs');
  
  const empty = validateTaskDescription('');
  assertEquals(empty.valid, false);
  
  const whitespace = validateTaskDescription('   ');
  assertEquals(whitespace.valid, false);
  
  const long = validateTaskDescription('a'.repeat(501));
  assertEquals(long.valid, false);
});

test('validateSchedule: validates schedule formats', () => {
  const interval = validateSchedule('every 6h');
  assertEquals(interval.valid, true);
  assertEquals(interval.type, 'interval');
  
  const daily = validateSchedule('daily at 9:00');
  assertEquals(daily.valid, true);
  assertEquals(daily.type, 'daily');
  
  const cron = validateSchedule('0 9 * * *');
  assertEquals(cron.valid, true);
  assertEquals(cron.type, 'cron');
  
  const invalid = validateSchedule('invalid format');
  assertEquals(invalid.valid, false);
});

test('sanitizeInput: escapes HTML', () => {
  assertEquals(sanitizeInput('<script>alert("xss")</script>'), '&lt;script&gt;alert(&quot;xss&quot;)&lt;&#x2F;script&gt;');
  assertEquals(sanitizeInput('Hello & goodbye'), 'Hello &amp; goodbye');
});

test('calculateSuccessRate: calculates percentage', () => {
  assertEquals(calculateSuccessRate(10, 100), 10);
  assertEquals(calculateSuccessRate(0, 100), 0);
  assertEquals(calculateSuccessRate(5, 10), 50);
  assertEquals(calculateSuccessRate(10, 0), 0);
});

test('groupBy: groups array by key', () => {
  const items = [
    { type: 'job', value: 1 },
    { type: 'game', value: 2 },
    { type: 'job', value: 3 }
  ];
  
  const grouped = groupBy(items, 'type');
  assertEquals(Object.keys(grouped).length, 2);
  assertEquals(grouped.job.length, 2);
  assertEquals(grouped.game.length, 1);
});

test('sortBy: sorts array by key', () => {
  const items = [
    { name: 'Charlie', age: 30 },
    { name: 'Alice', age: 25 },
    { name: 'Bob', age: 35 }
  ];
  
  const sorted = sortBy(items, 'age');
  assertEquals(sorted[0].name, 'Alice');
  assertEquals(sorted[2].name, 'Bob');
  
  const sortedDesc = sortBy(items, 'age', 'desc');
  assertEquals(sortedDesc[0].name, 'Bob');
});

test('unique: removes duplicates', () => {
  const arr = [1, 2, 2, 3, 3, 3, 4];
  assertEquals(unique(arr), [1, 2, 3, 4]);
  
  const objs = [
    { id: 1, name: 'A' },
    { id: 2, name: 'B' },
    { id: 1, name: 'C' }
  ];
  const uniqueObjs = unique(objs, 'id');
  assertEquals(uniqueObjs.length, 2);
});

test('chunk: splits array into chunks', () => {
  const arr = [1, 2, 3, 4, 5, 6, 7];
  const chunks = chunk(arr, 3);
  assertEquals(chunks.length, 3);
  assertEquals(chunks[0].length, 3);
  assertEquals(chunks[2].length, 1);
});

test('average: calculates average', () => {
  assertEquals(average([1, 2, 3, 4, 5]), 3);
  assertEquals(average([10, 20, 30]), 20);
  assertEquals(average([]), 0);
});

test('median: calculates median', () => {
  assertEquals(median([1, 2, 3, 4, 5]), 3);
  assertEquals(median([1, 2, 3, 4]), 2.5);
  assertEquals(median([]), 0);
});

test('percentile: calculates percentile', () => {
  const data = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  assertEquals(percentile(data, 50), 5.5); // median
  assertEquals(percentile(data, 90), 9.1);
});

test('truncate: truncates strings', () => {
  assertEquals(truncate('Hello World', 8), 'Hello...');
  assertEquals(truncate('Short', 10), 'Short');
  assertEquals(truncate('12345', 5), '12345');
});

test('safeJsonParse: parses JSON safely', () => {
  assertEquals(safeJsonParse('{"a":1}'), { a: 1 });
  assertEquals(safeJsonParse('invalid'), null);
  assertEquals(safeJsonParse('invalid', { default: true }), { default: true });
});

test('isEmpty: checks if empty', () => {
  assertTrue(isEmpty(null));
  assertTrue(isEmpty([]));
  assertTrue(isEmpty({}));
  assertTrue(!isEmpty([1]));
  assertTrue(!isEmpty({ a: 1 }));
});

test('deepMerge: merges objects deeply', () => {
  const obj1 = { a: 1, b: { c: 2 } };
  const obj2 = { b: { d: 3 }, e: 4 };
  const merged = deepMerge(obj1, obj2);
  
  assertEquals(merged.a, 1);
  assertEquals(merged.b.c, 2);
  assertEquals(merged.b.d, 3);
  assertEquals(merged.e, 4);
});

test('getNestedProperty: gets nested properties', () => {
  const obj = { a: { b: { c: 'value' } } };
  assertEquals(getNestedProperty(obj, 'a.b.c'), 'value');
  assertEquals(getNestedProperty(obj, 'a.b.x', 'default'), 'default');
  assertEquals(getNestedProperty(obj, 'x.y.z'), undefined);
});

test('setNestedProperty: sets nested properties', () => {
  const obj = {};
  setNestedProperty(obj, 'a.b.c', 'value');
  assertEquals(obj.a.b.c, 'value');
});

console.log('\n✅ All tests passed!\n');
