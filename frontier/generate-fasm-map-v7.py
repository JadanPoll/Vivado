#!/usr/bin/env python3
import argparse
import json
import os
import sys
import types


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prjxray-root', required=True)
    parser.add_argument('--db-root', required=True)
    parser.add_argument('--part', default='xc7s50csga324-1')
    parser.add_argument('--overlay-segbits')
    parser.add_argument('--overlay-block', default='CLB_IO_CLK')
    parser.add_argument('--output', required=True)
    args = parser.parse_args()

    # prjxray uses advisory POSIX locks even for read-only database access.
    if os.name == 'nt':
        sys.modules['fcntl'] = types.SimpleNamespace(
            LOCK_EX=0, LOCK_UN=0, flock=lambda *_: None)
    sys.path.insert(0, os.path.abspath(args.prjxray_root))
    import prjxray.db
    if os.name == 'nt':
        import prjxray.util
        prjxray.util.OpenSafeFile.lock_file = lambda self: None
        prjxray.util.OpenSafeFile.unlock_file = lambda self: None

    database = prjxray.db.Database(os.path.abspath(args.db_root), args.part)
    grid = database.grid()
    features = {}
    grid_entries = {}

    for tile_name in grid.tiles():
        location = grid.loc_of_tilename(tile_name)
        grid_info = grid.gridinfo_at_loc(location)
        tile_type = grid_info.tile_type
        bases = {}
        for block_type, bits in grid_info.bits.items():
            bases[block_type.value] = [
                bits.base_address, bits.frames, bits.offset, bits.words]
        grid_entries[tile_name] = {'type': tile_type, 'bases': bases}

        if tile_type in features:
            continue
        segment_bits = database.get_tile_segbits(tile_type)
        tile_features = {}
        for block_type, block_features in (segment_bits.segbits or {}).items():
            block_name = block_type.value
            for full_name, bit_list in block_features.items():
                name = full_name[len(tile_type) + 1:] if full_name.startswith(tile_type + '.') else full_name
                coordinates = [
                    [block_name, bit.word_column, bit.word_bit // 32, bit.word_bit % 32]
                    for bit in bit_list if bit.isset
                ]
                if coordinates:
                    tile_features[name] = coordinates[0] if len(coordinates) == 1 else coordinates
        features[tile_type] = tile_features

    if args.overlay_segbits:
        with open(args.overlay_segbits, encoding='utf-8') as overlay:
            for line in overlay:
                fields = line.split()
                if not fields or fields[0].startswith('#'):
                    continue
                full_name, *raw_bits = fields
                tile_type, name = full_name.split('.', 1)
                coordinates = []
                for raw_bit in raw_bits:
                    if raw_bit.startswith('!'):
                        continue
                    word_column, word_bit = map(int, raw_bit.split('_'))
                    coordinates.append([
                        args.overlay_block, word_column,
                        word_bit // 32, word_bit % 32])
                if coordinates:
                    features.setdefault(tile_type, {})[name] = (
                        coordinates[0] if len(coordinates) == 1 else coordinates)

    with open(args.output, 'w', encoding='utf-8', newline='') as output:
        json.dump({'grid': grid_entries, 'features': features}, output,
                  separators=(',', ':'))


if __name__ == '__main__':
    main()
