#!/usr/bin/env node
'use strict';

// Minimal, dependency-free Series-7 frame reader for focused differential
// experiments. It follows Project X-Ray's pinned Configuration logic: 101
// words per frame and two padding frames at row/half/block transitions.
const fs = require('node:fs');

function partFrames(filename) {
  const halves = {top: new Map(), bottom: new Map()};
  let half = null, row = null, bus = null, column = null;
  for (const line of fs.readFileSync(filename, 'utf8').split(/\r?\n/)) {
    let match;
    if ((match = /^  (top|bottom):/.exec(line))) half = match[1];
    else if ((match = /^      (\d+):/.exec(line))) row = Number(match[1]);
    else if ((match = /^          ([A-Z_]+):/.exec(line))) bus = match[1];
    else if ((match = /^              (\d+):/.exec(line))) column = Number(match[1]);
    else if ((match = /^                frame_count: (\d+)/.exec(line))) {
      if (half === null || row === null || bus === null || column === null)
        throw new Error('Malformed part YAML state');
      const rows = halves[half];
      if (!rows.has(row)) rows.set(row, new Map());
      const buses = rows.get(row);
      if (!buses.has(bus)) buses.set(bus, new Map());
      buses.get(bus).set(column, Number(match[1]));
    }
  }
  const blockTypes = new Map([['CLB_IO_CLK', 0], ['BLOCK_RAM', 1], ['CFG_CLB', 2]]);
  const frames = [];
  for (const [bus, block] of blockTypes) {
    for (const half of ['top', 'bottom']) {
      for (const row of [...halves[half].keys()].sort((a, b) => a - b)) {
        const columns = halves[half].get(row).get(bus);
        if (!columns) continue;
        for (const column of [...columns.keys()].sort((a, b) => a - b))
          for (let minor = 0; minor < columns.get(column); minor++)
            frames.push({address: (block << 23) | ((half === 'bottom' ? 1 : 0) << 22) |
              (row << 17) | (column << 7) | minor, block, half, row, column, minor});
      }
    }
  }
  return frames;
}

function packets(filename) {
  const bytes = fs.readFileSync(filename);
  const sync = bytes.indexOf(Buffer.from([0xaa, 0x99, 0x55, 0x66]));
  if (sync < 0) throw new Error('No Series-7 sync word in ' + filename);
  const result = [];
  let offset = sync + 4, lastAddress = 0;
  while (offset + 4 <= bytes.length) {
    const header = bytes.readUInt32BE(offset); offset += 4;
    const type = header >>> 29;
    if (type === 1) {
      const opcode = (header >>> 27) & 3;
      const address = (header >>> 13) & 0x3fff;
      const count = header & 0x7ff;
      lastAddress = address;
      const data = [];
      for (let i = 0; i < count; i++, offset += 4) data.push(bytes.readUInt32BE(offset));
      result.push({opcode, address, data});
    } else if (type === 2) {
      const opcode = (header >>> 27) & 3;
      const count = header & 0x7ffffff;
      const data = [];
      for (let i = 0; i < count; i++, offset += 4) data.push(bytes.readUInt32BE(offset));
      result.push({opcode, address: lastAddress, data});
    }
  }
  return result;
}

function readFrames(bitfile, orderedFrames) {
  const index = new Map(orderedFrames.map((frame, i) => [frame.address, i]));
  const output = new Map();
  let command = 0, far = 0, startWrite = false, current = 0;
  for (const packet of packets(bitfile)) {
    if (packet.opcode !== 2) continue;
    if (packet.address === 4 && packet.data.length) {
      command = packet.data[0];
      if (command === 1) startWrite = true;
    } else if (packet.address === 1 && packet.data.length) {
      far = packet.data[0];
      if (command === 1) startWrite = true;
    } else if (packet.address === 2) {
      if (startWrite) { current = far; startWrite = false; }
      let position = 0;
      while (position + 101 <= packet.data.length && index.has(current)) {
        output.set(current, packet.data.slice(position, position + 101));
        position += 101;
        const i = index.get(current), next = orderedFrames[i + 1];
        if (!next) break;
        const prior = orderedFrames[i];
        if (next.block !== prior.block || next.half !== prior.half || next.row !== prior.row)
          position += 202;
        current = next.address;
      }
    }
  }
  return output;
}

const [partFile, bitFile, rawAddress] = process.argv.slice(2);
if (!partFile || !bitFile || !rawAddress) {
  console.error('Usage: node frontier/inspect-xc7-bit.cjs PART.YAML DESIGN.BIT FRAME_ADDRESS');
  process.exit(2);
}
const address = Number(rawAddress);
const order = partFrames(partFile);
const words = readFrames(bitFile, order).get(address);
if (!words) throw new Error('Frame not found: 0x' + address.toString(16));
console.log(JSON.stringify({bitfile: bitFile, frame: '0x' + address.toString(16).padStart(8, '0'),
  words: words.map(word => '0x' + word.toString(16).padStart(8, '0'))}));
