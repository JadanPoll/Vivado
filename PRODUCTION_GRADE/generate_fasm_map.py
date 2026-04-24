#!/usr/bin/env python3
"""
Generates xc7s50_fasm_map_v2.json
Format: {"types": {tile_type: {feature: [block, wordCol, wordIdx, bitIdx]}},
          "grid":  {tile_name: [{block: base_addr}, tile_type]}}
CRITICAL FIX: wordIdx = bits.offset + (bit.word_bit // 32)
              NOT just bit.word_bit // 32
"""
import sys, json
sys.path.insert(0, '/workspaces/prjxray')
import prjxray.db

DB_ROOT = '/workspaces/nextpnr-xilinx/xilinx/external/prjxray-db/spartan7'
PART    = 'xc7s50csga324-1'
OUT     = '/workspaces/Vivado/PRODUCTION_GRADE/xc7s50_fasm_map_v2_new.json'

db   = prjxray.db.Database(DB_ROOT, PART)
grid = db.grid()

types_out = {}
grid_out  = {}

tiles = list(grid.tiles())
for idx, tile_name in enumerate(tiles):
    if idx % 2000 == 0:
        print(f'  {idx}/{len(tiles)} {tile_name}', flush=True)

    loc = grid.loc_of_tilename(tile_name)
    gi  = grid.gridinfo_at_loc(loc)
    tt  = gi.tile_type

    # Build grid entry: {block_name: base_address}
    bases = {}
    for block_type, bits in gi.bits.items():
        bases[block_type.value] = bits.base_address
    grid_out[tile_name] = [bases, tt]

    if tt in types_out:
        continue  # already processed this tile type

    sb = db.get_tile_segbits(tt)
    if not sb.segbits:
        types_out[tt] = {}
        continue

    feats = {}
    for block_type, block_feats in sb.segbits.items():
        bt_str = block_type.value
        # Get offset for this block type from grid info
        if block_type not in gi.bits:
            continue
        offset = gi.bits[block_type].offset   # <-- THE CRITICAL FIX

        for full_feat_name, bits_list in block_feats.items():
            # Strip tile type prefix: "LIOB33.IOB_Y0.FOO" -> "IOB_Y0.FOO"
            feat_key = full_feat_name
            if feat_key.startswith(tt + '.'):
                feat_key = feat_key[len(tt)+1:]

            coords = []
            for bit in bits_list:
                if not bit.isset:
                    continue
                word_idx = offset + (bit.word_bit // 32)  # FIXED
                bit_idx  = bit.word_bit % 32
                coords.append([bt_str, bit.word_column, word_idx, bit_idx])

            if not coords:
                continue
            val = coords[0] if len(coords) == 1 else coords
            feats[feat_key] = val

    types_out[tt] = feats

print(f'Writing {OUT}...')
with open(OUT, 'w') as f:
    json.dump({'types': types_out, 'grid': grid_out}, f, separators=(',', ':'))

print(f'Done. Tile types: {len(types_out)}, Tiles: {len(grid_out)}')
