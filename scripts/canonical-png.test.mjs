import assert from "node:assert/strict";
import { test } from "node:test";
import { PNG } from "pngjs";
import { canonicalPng } from "./canonical-png.mjs";

function fixture() {
  const image = new PNG({ width: 13, height: 7 });
  for (let i = 0; i < image.data.length; i += 4) {
    image.data[i] = i % 256;
    image.data[i + 1] = (i * 3) % 256;
    image.data[i + 2] = (i * 7) % 256;
    image.data[i + 3] = 255;
  }
  return image;
}

test("equivalent PNG encoders produce identical canonical evidence", () => {
  const image = fixture();
  const rgb = PNG.sync.write(image, { colorType: 2, filterType: 0, deflateLevel: 1 });
  const rgba = PNG.sync.write(image, { colorType: 6, filterType: 4, deflateLevel: 9 });
  assert.notDeepEqual(rgb, rgba);
  assert.deepEqual(canonicalPng(rgb), canonicalPng(rgba));
  assert.deepEqual(PNG.sync.read(canonicalPng(rgb)).data, image.data);
  assert.deepEqual(canonicalPng(canonicalPng(rgb)), canonicalPng(rgb));
});

test("one changed pixel still changes the exact evidence bytes", () => {
  const image = fixture();
  const before = canonicalPng(PNG.sync.write(image));
  image.data[0] ^= 1;
  assert.notDeepEqual(before, canonicalPng(PNG.sync.write(image)));
});

test("damaged PNG input is rejected", () => {
  assert.throws(() => canonicalPng(Buffer.from("not a screenshot")));
  const damaged = PNG.sync.write(fixture());
  damaged[29] ^= 1; // IHDR CRC
  assert.throws(() => canonicalPng(damaged));
});
