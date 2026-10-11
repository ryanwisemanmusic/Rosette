"""Bounded, selected retail tag metadata checks. Never rendering attestations.

Only reference-bearing branches and selected effect/light numeric fields from
the pinned Assembly Halo3 layouts are inspected. Resource data is not decoded.
"""
from collections import Counter
import hashlib
import html
import json
import math
from pathlib import Path
import struct
import xml.etree.ElementTree as ET

from .iso import InventoryError, hash_file, inventory
from .iso_offline import CacheReader, u32

CLASSES = ('effe', 'ligh', 'lens', 'mode', 'sefc')
REVISION = 'fd14ef3c46135e9422966c6a64cd926fb0bd23fb'
NUMERIC = {'float32': 1, 'rangef': 2, 'colorf': 3}
MAX_BLOCK = 8192
MAX_FIELDS = 65536


def layout(path):
    data = path.read_bytes()
    if len(data) > 1 << 20 or b'<!DOCTYPE' in data or b'<!ENTITY' in data:
        raise InventoryError('Unsafe or oversized layout XML')
    root = ET.fromstring(data)
    if root.tag != 'plugin' or root.get('game') != 'Halo3':
        raise InventoryError('Not a Halo3 layout')
    numeric = path.stem in ('effe', 'ligh', 'lens', 'sefc')

    def fields(node, size, depth=0):
        if depth > 12 or not 0 < size <= 1 << 20:
            raise InventoryError('Layout depth or size exceeds bounds')
        result = []
        for child in node:
            kind = child.tag
            if kind not in ('tagRef', 'tagblock') and not (numeric and kind in NUMERIC):
                continue
            offset = int(child.get('offset'), 0)
            record = {'kind': kind, 'name': child.get('name', kind), 'offset': offset}
            if kind == 'tagblock':
                element = int(child.get('elementSize'), 0)
                record.update(size=element, fields=fields(child, element, depth + 1))
                if not record['fields']:
                    continue
                length = 12
            elif kind == 'tagRef':
                length = 16
            else:
                record['components'] = 4 if kind == 'colorf' and child.get('alpha') == 'true' else NUMERIC[kind]
                length = 4 * record['components']
            if offset < 0 or offset + length > size:
                raise InventoryError('Selected layout field exceeds structure')
            result.append(record)
        return result
    size = int(root.get('baseSize'), 0)
    return {'size': size, 'fields': fields(root, size), 'path': str(path.resolve()), 'sha256': hashlib.sha256(data).hexdigest(),
            'source': f'https://github.com/XboxChaos/Assembly/blob/{REVISION}/src/Assembly/Plugins/Halo3/{path.stem}.xml'}


def map_tags(reader):
    header = reader.read(0, 12288)
    index = reader.read(u32(header, 16) - reader.magic, 16)
    class_count, class_pointer, count, pointer = struct.unpack('>4I', index)
    if not 0 < class_count <= 512 or not 0 < count <= 100000:
        raise InventoryError('Tag index bounds differ from inventory')
    classes = reader.pointer(class_pointer, class_count * 16)
    tags = reader.pointer(pointer, count * 8)
    result = []
    for i in range(count):
        cls, salt, pointer = struct.unpack_from('>hHI', tags, i * 8)
        if cls == -1:
            result.append(None)
        elif 0 <= cls < class_count:
            codes = tuple(classes[cls * 16 + n:cls * 16 + n + 4].decode('latin1') for n in (0, 4, 8))
            result.append({'class': codes[0], 'parents': codes[1:], 'salt': salt, 'pointer': pointer})
        else:
            raise InventoryError('Class outside table')
    return result


def inspect(reader, asset, schema, tags, asset_ids):
    result = {'asset_id': asset['id'], 'class': asset['class'], 'name': asset['name'], 'map': asset['map'],
              'status': 'unknown', 'references': [], 'numeric_fields': [], 'blocks_checked': 0}
    touched = hashlib.sha256()
    count = 0

    def walk(offset, size, fields, path, ancestors):
        nonlocal count
        if offset in ancestors:
            raise InventoryError('Cycle in selected metadata block')
        raw = reader.read(offset, size)
        touched.update(struct.pack('>QQ', offset, size) + raw)
        for field in fields:
            count += 1
            if count > MAX_FIELDS:
                raise InventoryError('Per-asset selected field limit exceeded')
            loc = field['offset']
            label = f"{path}/{field['name']}"
            if field['kind'] == 'tagblock':
                n, ptr = struct.unpack_from('>II', raw, loc)
                if n > MAX_BLOCK or n * field['size'] > 16 << 20 or (n and ptr == 0):
                    raise InventoryError('Selected tagblock count/pointer outside bounds')
                result['blocks_checked'] += 1
                if n:
                    # Verify entire extent before walking its selected fields.
                    reader.pointer(ptr, n * field['size'])
                for i in range(n):
                    walk(ptr - reader.magic + i * field['size'], field['size'], field['fields'], f'{label}[{i}]', ancestors | {offset})
            elif field['kind'] == 'tagRef':
                cls = raw[loc:loc + 4].decode('latin1')
                datum = u32(raw, loc + 12)
                ref = {'field': label, 'offset': offset + loc, 'class': cls, 'datum': datum}
                if datum == 0xffffffff:
                    ref['status'] = 'null'
                else:
                    i, salt = datum & 0xffff, datum >> 16
                    target = tags[i] if i < len(tags) else None
                    if target is None:
                        ref.update(status='unresolved', reason='datum outside or vacant in owning map')
                    elif salt != target['salt']:
                        ref.update(status='unresolved', reason='datum salt differs', table_salt=target['salt'])
                    elif cls not in (target['class'], *target['parents']):
                        ref.update(status='unresolved', reason='class differs from target hierarchy', target_class=target['class'])
                    else:
                        ref.update(status='resolved', target_index=i, target_class=target['class'], target_asset_id=asset_ids.get((asset['map'], i)))
                result['references'].append(ref)
            else:
                values = struct.unpack_from(f">{field['components']}f", raw, loc)
                result['numeric_fields'].append({'field': label, 'offset': offset + loc,
                                                 'values': [v if math.isfinite(v) else None for v in values],
                                                 'finite': all(math.isfinite(v) for v in values)})
    try:
        walk(asset['metadata_offset'], schema['size'], schema['fields'], asset['class'], set())
        result['status'] = 'pass' if all(r['status'] != 'unresolved' for r in result['references']) and all(r['finite'] for r in result['numeric_fields']) else 'needs_review'
    except (InventoryError, struct.error) as error:
        result['reason'] = str(error)
    result['metadata_reads_sha256'] = touched.hexdigest()
    return result


def check_tags(snapshot, schemas, output, per_class=100):
    if not 1 <= per_class <= 1000:
        raise InventoryError('Per-class limit must be 1..1000')
    layouts = {cls: layout(schemas / f'{cls}.xml') for cls in CLASSES}
    fresh = inventory(Path(snapshot['iso']['path']))
    for key in ('sha256', 'denominator_sha256', 'files'):
        if fresh[key] != snapshot['iso'][key]:
            raise InventoryError('Fresh ISO inventory differs from saved baseline')
    current = {a['id']: a for a in fresh['assets']}
    if any(a['metadata_offset'] != current[a['id']]['metadata_offset'] for a in snapshot['iso']['assets']):
        raise InventoryError('Saved tag offsets differ from fresh inventory')
    selected, counts = [], Counter()
    for asset in sorted(fresh['assets'], key=lambda a: (a['map'], a['tag_index'])):
        if asset['class'] in layouts and counts[asset['class']] < per_class:
            selected.append(asset); counts[asset['class']] += 1
    output.mkdir(parents=True, exist_ok=False)
    ids = {(a['map'], a['tag_index']): a['id'] for a in fresh['assets']}
    files = {f['path']: f for f in fresh['files']}
    readers, tables, results = {}, {}, []
    before = Path(fresh['path']).stat()
    with Path(fresh['path']).open('rb') as stream:
        for asset in selected:
            name = asset['map']
            if name not in readers:
                readers[name] = CacheReader(stream, files[name], fresh['size'])
                tables[name] = map_tags(readers[name])
            results.append(inspect(readers[name], asset, layouts[asset['class']], tables[name], ids))
    after = Path(fresh['path']).stat()
    if (before.st_size, before.st_mtime_ns, before.st_ino) != (after.st_size, after.st_mtime_ns, after.st_ino):
        raise InventoryError('ISO changed during metadata checks')
    result = {'schema': 'rosette-selected-tag-metadata-v1', 'iso_sha256': fresh['sha256'], 'layouts': layouts,
              'tool_sha256': hash_file(Path(__file__)), 'tool': str(Path(__file__).resolve()), 'per_class_limit': per_class,
              'scope': 'Selected reference-bearing branches and finite light/effect numeric fields only. No resource, shader binding, simulation or rendering proof.', 'assets': results}
    manifest = output / 'manifest.json'
    manifest.write_text(json.dumps(result, indent=2, allow_nan=False))
    snapshot['tag_checks'] = {'manifest': str(manifest.resolve()), 'sha256': hash_file(manifest), 'result': result}
    return tag_summary(snapshot)


def tag_summary(snapshot):
    record = snapshot.get('tag_checks')
    if not record:
        return None
    r = record['result']; stale = []
    checks = [(record['manifest'], record['sha256']), (r['tool'], r['tool_sha256'])]
    checks += [(x['path'], x['sha256']) for x in r['layouts'].values()]
    for path, sha in checks:
        try: valid = hash_file(Path(path)) == sha
        except OSError: valid = False
        if not valid: stale.append(path)
    # Embedded results must remain identical to the hashed manifest.
    try:
        if json.loads(Path(record['manifest']).read_text()) != r: stale.append('embedded result differs')
    except (OSError, ValueError): stale.append('manifest unreadable')
    groups = {}
    for cls in CLASSES:
        items = [a for a in r['assets'] if a['class'] == cls]
        groups[cls] = {'tested': len(items), 'pass': sum(a['status'] == 'pass' for a in items) if not stale else 0,
                       'needs_review': sum(a['status'] == 'needs_review' for a in items) if not stale else 0,
                       'unknown': len(items) if stale else sum(a['status'] == 'unknown' for a in items)}
    return {'groups': groups, 'stale': stale, 'tested': len(r['assets']),
            'references': dict(Counter(x['status'] for a in r['assets'] for x in a['references'])) if not stale else {},
            'scope': r['scope']}


def tag_view(snapshot):
    s = tag_summary(snapshot)
    if s is None: return ''
    esc = lambda v: html.escape(str(v))
    rows = ''.join(f"<tr><td>{esc(k)}</td><td>{v['tested']}</td><td>{v['pass']}</td><td>{v['needs_review']}</td><td>{v['unknown']}</td></tr>" for k,v in s['groups'].items())
    records = ''.join(f"<tr><td>{esc(a['map'])} / {esc(a['class'])}</td><td>{esc(a['name'])}</td><td>{esc('unknown' if s['stale'] else a['status'])}</td><td>{len(a['references'])}</td><td>{esc(a.get('reason',''))}</td></tr>" for a in snapshot['tag_checks']['result']['assets'])
    return f'''<section id="tag-checks"><h2>Selected effect, lighting and geometry metadata checks</h2>
<p>{esc(s['scope'])} All ISO rendering correctness counters remain separate.</p>
<p>{s['tested']} selected tag instances · reference results {esc(s['references'])} · stale evidence {len(s['stale'])}</p>
<table><thead><tr><th>Class</th><th>Tested</th><th>Selected fields pass</th><th>Needs review</th><th>Unknown</th></tr></thead><tbody>{rows}</tbody></table>
<details><summary>All selected tags and metadata results</summary><div class="scroll"><table><thead><tr><th>Map / class</th><th>Tag</th><th>Check</th><th>References</th><th>Gap</th></tr></thead><tbody>{records}</tbody></table></div></details>
<details><summary>Layout provenance and full dependency graph</summary><p>Full resolved/null/unresolved edges and numeric values are saved in the tag-check manifest named in snapshot.json.</p><pre>{esc(json.dumps({k:v for k,v in snapshot['tag_checks']['result'].items() if k!='assets'},indent=2))}</pre></details></section>'''
