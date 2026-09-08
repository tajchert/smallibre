#!/usr/bin/env python3
"""Independent, stdlib-only diagnostic for Smallibre's bounded C1 KF8 profile.
Not a general MOBI decoder or a substitute for reading on hardware.
"""
import argparse
import json
from pathlib import Path
import re
import struct
import uuid


def require(ok, message):
    if not ok:
        raise ValueError(message)


def span(data, start, size):
    require(0 <= start <= len(data) and 0 <= size <= len(data) - start, 'out-of-bounds byte range')
    return data[start:start + size]


def word(data, offset, size=4):
    return int.from_bytes(span(data, offset, size), 'big')


def vint(data, pos):
    value = 0
    for _ in range(5):
        byte = word(data, pos, 1)
        pos += 1
        value = (value << 7) | (byte & 127)
        if byte & 128:
            return value, pos
    raise ValueError('unterminated/oversized index integer')


def index(records, number):
    require(0 <= number < len(records), 'missing index record')
    head = records[number]
    require(head[:4] == b'INDX' and word(head, 4) == 192, 'unsupported index header')
    count, strings = word(head, 24), word(head, 52)
    require(count > 0 and number + count + strings < len(records), 'index record range')
    tx = word(head, 180)
    require(span(head, tx, 4) == b'TAGX', 'missing TAGX')
    length, controls = word(head, tx + 4), word(head, tx + 8)
    require(length >= 12 and (length - 12) % 4 == 0 and controls == 1, 'unsupported TAGX shape')
    definitions = list(struct.iter_unpack('BBBB', span(head, tx + 12, length - 12)))
    entries = []
    for record in records[number + 1:number + count + 1]:
        require(record[:4] == b'INDX', 'missing index data')
        table, total = word(record, 20), word(record, 24)
        require(span(record, table, 4) == b'IDXT', 'missing IDXT')
        offsets = [word(record, table + 4 + i * 2, 2) for i in range(total)] + [table]
        require(all(192 <= a < b <= table for a, b in zip(offsets, offsets[1:])), 'invalid index entry offsets')
        for start, end in zip(offsets, offsets[1:]):
            data = span(record, start, end - start)
            n = word(data, 0, 1)
            name = span(data, 1, n).decode('utf-8')
            control = word(data, n + 1, 1)
            cursor = n + 2
            pending = []
            for tag, arity, mask, stop in definitions:
                if stop:
                    continue
                require(mask and arity, 'invalid tag definition')
                bits = control & mask
                if not bits:
                    continue
                if bits == mask and mask.bit_count() > 1:
                    size, cursor = vint(data, cursor)
                    pending.append((tag, arity, None, size))
                else:
                    repetitions = bits // (mask & -mask)
                    pending.append((tag, arity, repetitions * arity, None))
            tags = {}
            for tag, arity, number_values, byte_count in pending:
                values = []
                if number_values is not None:
                    for _ in range(number_values):
                        value, cursor = vint(data, cursor)
                        values.append(value)
                else:
                    stop = cursor + byte_count
                    while cursor < stop:
                        value, cursor = vint(data, cursor)
                        values.append(value)
                    require(cursor == stop and len(values) % arity == 0, 'tag byte count mismatch')
                require(tag not in tags, 'duplicate tag')
                tags[tag] = values
            require(not any(data[cursor:]), 'unparsed index bytes')
            entries.append((name, tags))
    require(len(entries) == word(head, 36), 'index total mismatch')
    cncx = {}
    for ordinal, record in enumerate(records[number + count + 1:number + count + strings + 1]):
        pos = 0
        while pos < len(record):
            if not any(record[pos:]):
                break
            offset = pos + ordinal * 65536
            size, pos = vint(record, pos)
            cncx[offset] = span(record, pos, size).decode('utf-8')
            pos += size
    return entries, cncx


def inspect(path, output):
    require(path.stat().st_size <= 256 * 1024 * 1024, 'file exceeds diagnostic bound')
    data = path.read_bytes()
    require(span(data, 60, 8) == b'BOOKMOBI', 'not BOOKMOBI')
    count = word(data, 76, 2)
    require(2 <= count <= 10000, 'record count outside bound')
    offsets = [word(data, 78 + i * 8) for i in range(count)] + [len(data)]
    require(offsets[0] >= 78 + count * 8 and all(a < b for a, b in zip(offsets, offsets[1:])), 'invalid PalmDB record directory')
    records = [span(data, a, b - a) for a, b in zip(offsets, offsets[1:])]
    head = records[0]
    require(span(head, 16, 4) == b'MOBI' and word(head, 36) == 8 and word(head, 104) == 8, 'requires standalone KF8')
    require(word(head, 0, 2) == 1 and word(head, 12, 2) == 0, 'requires uncompressed, unencrypted text')
    require(word(head, 28) == 65001 and word(head, 242, 2) == 0, 'requires UTF-8 without text trailers')
    exth_start = 16 + word(head, 20)
    require(word(head, 128) & 64 and span(head, exth_start, 4) == b'EXTH', 'missing EXTH metadata')
    exth_length, exth_count = word(head, exth_start + 4), word(head, exth_start + 8)
    exth = span(head, exth_start, exth_length)
    cursor = 12
    identifiers = []
    for _ in range(exth_count):
        size = word(exth, cursor + 4)
        require(size >= 8, 'invalid EXTH entry length')
        span(exth, cursor, size)
        if word(exth, cursor) == 113:
            identifiers.append(span(exth, cursor + 8, size - 8).decode("ascii"))
        cursor += size
    require(not any(exth[cursor:]), 'unparsed EXTH bytes')
    require(len(identifiers) == 1, 'expected one EXTH 113 document identifier for Kindle navigation')
    require(str(uuid.UUID(identifiers[0])) == identifiers[0].lower(), 'invalid document UUID')
    text_count, text_length = word(head, 8, 2), word(head, 4)
    require(0 < text_count < count, 'invalid text record count')
    raw = b''.join(records[1:text_count + 1])
    require(len(raw) == text_length, 'text byte length mismatch')
    raw.decode('utf-8')
    auxiliary = {}
    for signature, pointer_offset, fields in (
        (b'FCIS', 200, (20, 16, 2, 0, text_length, 0, 40, 0, 40, 8, 65537, 0)),
        (b'FLIS', 208, (8, 4259840, 0, 4294967295, 65539, 3, 1, 4294967295)),
    ):
        number = word(head, pointer_offset)
        require(word(head, pointer_offset + 4) == 1 and text_count < number < count, 'invalid auxiliary record pointer/count')
        record = records[number]
        require(len(record) == 4 + 4 * len(fields) and record[:4] == signature, 'invalid auxiliary record signature/size')
        require(tuple(word(record, 4 + 4 * i) for i in range(len(fields))) == fields, 'unsupported ' + signature.decode() + ' fields')
        auxiliary[signature.decode()] = number
    require(len(set(auxiliary.values())) == 2, 'auxiliary records overlap')
    fdst = word(head, 192)
    require(fdst < count and records[fdst][:4] == b'FDST', 'missing FDST')
    flow_count = word(records[fdst], 8)
    require(flow_count == word(head, 196) and flow_count >= 1, 'flow count mismatch')
    flows = [(word(records[fdst], 12 + i * 8), word(records[fdst], 16 + i * 8)) for i in range(flow_count)]
    require(flows[0][0] == 0 and flows[-1][1] == len(raw), 'flow coverage mismatch')
    for i, (start, end) in enumerate(flows):
        span(raw, start, end - start).decode('utf-8')
        require(i == 0 or start == flows[i - 1][1], 'noncontiguous flows')
    skeletons, _ = index(records, word(head, 252))
    fragments, selectors = index(records, word(head, 248))
    parts, locations = [], []
    frag = 0
    expected_start = 0
    for file_number, (_, tags) in enumerate(skeletons):
        require(len(tags[1]) == 2 and tags[1][0] == tags[1][1], 'skeleton count duplication mismatch')
        require(len(tags[6]) == 4 and tags[6][:2] == tags[6][2:], 'skeleton geometry duplication mismatch')
        start, length = tags[6][:2]
        require(start == expected_start, 'chapter text gap/overlap')
        part = span(raw, start, length)
        cursor = start + length
        for _ in range(tags[1][0]):
            require(frag < len(fragments), 'missing fragment')
            name, fields = fragments[frag]
            require(fields[3] == [file_number] and fields[4] == [frag], 'fragment file/sequence mismatch')
            require(fields[2][0] in selectors, 'missing fragment selector')
            selector = selectors[fields[2][0]]
            parent = re.fullmatch(r"P-//\*\[@aid='([0-9A-V]+)'\]", selector)
            require(parent is not None, 'unsupported fragment selector: expected parent P- selector')
            parent_tag = re.search(rb'<body\b[^>]*\baid="' + parent[1].encode('ascii') + rb'"[^>]*>', part)
            require(parent_tag is not None, 'fragment selector does not resolve to skeleton body')
            require(int(name) - start == parent_tag.end(), 'fragment insertion does not follow selected parent opening tag')
            relative, size = fields[6]
            insertion = int(name) - start
            require(relative == cursor - start - length and 0 <= insertion <= len(part), 'invalid fragment insertion/relative start')
            chunk = span(raw, cursor, size)
            chunk.decode('utf-8')
            part[:insertion].decode('utf-8')
            part = part[:insertion] + chunk + part[insertion:]
            locations.append((file_number, insertion, size))
            cursor += size
            frag += 1
        require(cursor <= flows[0][1], 'chapter outside main flow')
        parts.append(part)
        expected_start = cursor
    require(frag == len(fragments) and expected_start == flows[0][1], 'unused fragments/main-flow bytes')

    def target(fid, offset):
        require(fid < len(locations), 'link references absent fragment')
        file_number, insertion, size = locations[fid]
        require(0 <= offset < size, 'link outside fragment')
        pos = insertion + offset
        parts[file_number][:pos].decode('utf-8')
        require(parts[file_number][pos:pos + 1] == b'<', 'target is not at a tag byte boundary')
        return {'chapter': file_number + 1, 'utf8_byte_offset': pos}

    links, images = [], []
    for part in parts:
        for fid, off in re.findall(rb'kindle:pos:fid:([0-9A-V]+):off:([0-9A-V]+)', part):
            links.append(target(int(fid, 32), int(off, 32)))
        for ref in re.findall(rb'kindle:embed:([0-9A-V]+)', part):
            number = word(head, 108) + int(ref, 32) - 1
            require(0 <= number < count and records[number].startswith((b'\x89PNG\r\n\x1a\n', b'\xff\xd8\xff', b'GIF8')), 'invalid image reference/signature')
            images.append(number)
    navigation, labels = index(records, word(head, 244))
    nav = []
    for _, fields in navigation:
        require(fields[3][0] in labels, 'missing navigation label')
        require(0 <= fields[1][0] < flows[0][1] and 0 <= fields[2][0] <= flows[0][1] - fields[1][0], 'navigation text range invalid')
        destination = target(*fields[6])
        nav.append({'label': labels[fields[3][0]], **destination})
    title = span(head, word(head, 84), word(head, 88)).decode('utf-8')
    if output:
        output.mkdir(parents=True, exist_ok=False)
        for i, part in enumerate(parts, 1):
            (output / f'chapter-{i}.xhtml').write_bytes(part)
    return {'title': title, 'records': count, 'text_bytes': len(raw), 'flows': flows, 'chapters': len(parts), 'auxiliary_records': auxiliary, 'links': links, 'image_records': images, 'navigation': nav, 'validation_scope': 'bounded C1 structure only; no hardware certification'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('azw3', type=Path)
    parser.add_argument('--extract', type=Path, help='new directory for reconstructed XHTML')
    args = parser.parse_args()
    try:
        print(json.dumps(inspect(args.azw3, args.extract), ensure_ascii=False, indent=2))
    except (ValueError, IndexError, KeyError, OSError) as error:
        parser.exit(1, f'Invalid/unsupported prototype: {error}\n')
