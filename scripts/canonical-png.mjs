import { PNG } from "pngjs";

// Chromium versions can choose different PNG filters/compression for exactly
// the same pixels. Keep strict, byte-for-byte evidence without making the
// browser's incidental encoder part of the game's visual contract.
export function canonicalPng(bytes) {
  const image = PNG.sync.read(bytes, { checkCRC: true });
  return PNG.sync.write(image, {
    bitDepth: 8,
    inputColorType: 6,
    colorType: 6,
    filterType: 4,
    deflateLevel: 9,
    deflateStrategy: 3,
  });
}
