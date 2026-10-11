#!/usr/bin/env python3
"""Per-draw shader constants out of a GFXReconstruct capture (gfxrecon-convert --format jsonl
--include-binaries), without replaying anything on a GPU.

The capture records Rosette's host Vulkan stream: initial buffer contents (InitBufferCommand),
CPU writes to mapped memory (FillMemoryCommand), descriptor writes, binds with dynamic offsets,
push constants and draws. Replaying that bookkeeping and reading every bound uniform buffer at
the submit that executes a draw gives exactly the constants the GPU saw for that draw.

    capture_constants.py FRAME.jsonl --out DIR

writes DIR/draws.jsonl (one record per executed draw/dispatch: pipeline, shader modules, and
each bound uniform buffer's bytes as float32 vec4 rows) and DIR/modules.json (SPIR-V module
id -> binary path, size, sha256). No Xenia, no GPU work.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

UNIFORM_TYPES = {'VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER', 'VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC'}
DYNAMIC_TYPES = {'VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC', 'VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC'}
MAX_TRACKED_MEMORY = 1 << 30


def name_of(record):
    return (record.get('function') or {}).get('name') or (record.get('meta') or {}).get('name')


class Capture:
    def __init__(self, root: Path):
        self.root = root
        self.buffers = {}          # buffer id -> {size, usage, memory, offset}
        self.memory_size = {}      # memory id -> allocation size
        self.memory = {}           # memory id -> bytearray (lazily created)
        self.set_layouts = {}      # layout id -> {binding: (type, count)}
        self.pipeline_layouts = {} # layout id -> [set layout ids]
        self.sets = {}             # set id -> {'layout': id, 'bindings': {binding: [descriptor]}}
        self.modules = {}          # module id -> {path, size, sha256}
        self.pipelines = {}        # pipeline id -> {stage: module id, 'bind_point': ...}
        self.recordings = {}       # command buffer -> list of draw snapshots
        self.images = {}           # image id -> {format, extent, mips, layers}
        self.views = {}            # view id -> {image, format, components}
        self.state = {}            # command buffer -> live bind state

    # -- memory ----------------------------------------------------------------------------
    def mem(self, memory_id):
        size = self.memory_size.get(memory_id, 0)
        if memory_id not in self.memory and 0 < size <= MAX_TRACKED_MEMORY:
            self.memory[memory_id] = bytearray(size)
        return self.memory.get(memory_id)

    def write_memory(self, memory_id, offset, data):
        target = self.mem(memory_id)
        if target is None:
            return
        end = min(len(target), offset + len(data))
        if offset < end:
            target[offset:end] = data[:end - offset]

    def read_buffer(self, buffer_id, offset, size):
        buffer = self.buffers.get(buffer_id)
        if not buffer or buffer.get('memory') is None:
            return None
        target = self.mem(buffer['memory'])
        if target is None:
            return None
        start = buffer['offset'] + offset
        return bytes(target[start:start + size])

    def blob(self, relative):
        return (self.root / relative).read_bytes()

    # -- records ---------------------------------------------------------------------------
    def handle(self, record):
        self.current_index = record.get('index')
        name = name_of(record)
        args = ((record.get('function') or record.get('meta') or {}).get('args')) or {}
        method = getattr(self, 'on_' + name, None) if name else None
        if method:
            method(args)

    def on_vkAllocateMemory(self, a):
        self.memory_size[a['pMemory']] = a['pAllocateInfo']['allocationSize']

    def on_vkCreateBuffer(self, a):
        info = a['pCreateInfo']
        self.buffers[a['pBuffer']] = {'size': info['size'], 'usage': int(info['usage'], 16), 'memory': None, 'offset': 0}

    def on_vkBindBufferMemory(self, a):
        if a['buffer'] in self.buffers:
            self.buffers[a['buffer']].update(memory=a['memory'], offset=a['memoryOffset'])

    def on_vkBindBufferMemory2(self, a):
        for info in a.get('pBindInfos') or []:
            if info['buffer'] in self.buffers:
                self.buffers[info['buffer']].update(memory=info['memory'], offset=info['memoryOffset'])

    def on_InitBufferCommand(self, a):
        buffer = self.buffers.get(a['buffer_id'])
        if buffer and buffer.get('memory') is not None and a.get('data'):
            self.write_memory(buffer['memory'], buffer['offset'], self.blob(a['data']))

    def on_FillMemoryCommand(self, a):
        if a.get('data'):
            self.write_memory(a['memory_id'], a['offset'], self.blob(a['data']))

    def on_vkCreateImage(self, a):
        info = a['pCreateInfo']
        self.images[a['pImage']] = {'format': info['format'], 'extent': [info['extent']['width'], info['extent']['height'], info['extent']['depth']],
                                    'mips': info['mipLevels'], 'layers': info['arrayLayers']}

    def on_vkCreateImageView(self, a):
        info = a['pCreateInfo']
        comp = info.get('components') or {}
        self.views[a['pView']] = {'image': info['image'], 'format': info['format'],
                                  'components': [comp.get(c) for c in ('r', 'g', 'b', 'a')]}

    def on_vkCreateDescriptorSetLayout(self, a):
        bindings = {}
        for b in a['pCreateInfo'].get('pBindings') or []:
            bindings[b['binding']] = (b['descriptorType'], b['descriptorCount'])
        self.set_layouts[a['pSetLayout']] = bindings

    def on_vkCreatePipelineLayout(self, a):
        self.pipeline_layouts[a['pPipelineLayout']] = list(a['pCreateInfo'].get('pSetLayouts') or [])

    def on_vkAllocateDescriptorSets(self, a):
        layouts = a['pAllocateInfo'].get('pSetLayouts') or []
        for set_id, layout in zip(a.get('pDescriptorSets') or [], layouts):
            self.sets[set_id] = {'layout': layout, 'bindings': {}}

    def on_vkUpdateDescriptorSets(self, a):
        for w in a.get('pDescriptorWrites') or []:
            target = self.sets.setdefault(w['dstSet'], {'layout': None, 'bindings': {}})
            slots = target['bindings'].setdefault(w['dstBinding'], {})
            infos = w.get('pBufferInfo') or w.get('pImageInfo') or w.get('pTexelBufferView') or []
            for i, info in enumerate(infos):
                slots[w['dstArrayElement'] + i] = (w['descriptorType'], info)
        for c in a.get('pDescriptorCopies') or []:
            source = self.sets.get(c['srcSet'], {}).get('bindings', {}).get(c['srcBinding'], {})
            target = self.sets.setdefault(c['dstSet'], {'layout': None, 'bindings': {}})
            slots = target['bindings'].setdefault(c['dstBinding'], {})
            for i in range(c['descriptorCount']):
                if c['srcArrayElement'] + i in source:
                    slots[c['dstArrayElement'] + i] = source[c['srcArrayElement'] + i]

    def on_vkCreateShaderModule(self, a):
        path = self.root / a['pCreateInfo']['pCode']
        data = path.read_bytes()
        self.modules[a['pShaderModule']] = {'path': str(path), 'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}

    def on_vkCreateGraphicsPipelines(self, a):
        for info, pipeline in zip(a['pCreateInfos'], a['pPipelines']):
            stages = {s['stage']: s['module'] for s in info.get('pStages') or []}
            self.pipelines[pipeline] = {'bind_point': 'graphics', 'stages': stages, 'layout': info.get('layout')}

    def on_vkCreateComputePipelines(self, a):
        for info, pipeline in zip(a['pCreateInfos'], a['pPipelines']):
            self.pipelines[pipeline] = {'bind_point': 'compute', 'stages': {info['stage']['stage']: info['stage']['module']}, 'layout': info.get('layout')}

    def on_vkBeginCommandBuffer(self, a):
        self.recordings[a['commandBuffer']] = []
        self.state[a['commandBuffer']] = {'pipeline': {}, 'sets': {}, 'push': {}}

    def on_vkCmdBindPipeline(self, a):
        point = 'compute' if 'COMPUTE' in a['pipelineBindPoint'] else 'graphics'
        self.state.setdefault(a['commandBuffer'], {'pipeline': {}, 'sets': {}, 'push': {}})['pipeline'][point] = a['pipeline']

    def on_vkCmdBindDescriptorSets(self, a):
        point = 'compute' if 'COMPUTE' in a['pipelineBindPoint'] else 'graphics'
        st = self.state.setdefault(a['commandBuffer'], {'pipeline': {}, 'sets': {}, 'push': {}})
        offsets = list(a.get('pDynamicOffsets') or [])
        for i, set_id in enumerate(a.get('pDescriptorSets') or []):
            layout = self.sets.get(set_id, {}).get('layout')
            bindings = self.set_layouts.get(layout, {})
            dynamic = sum(count for b, (t, count) in sorted(bindings.items()) if t in DYNAMIC_TYPES)
            mine, offsets = offsets[:dynamic], offsets[dynamic:]
            st['sets'][(point, a['firstSet'] + i)] = (set_id, mine)

    def on_vkCmdPushConstants(self, a):
        st = self.state.setdefault(a['commandBuffer'], {'pipeline': {}, 'sets': {}, 'push': {}})
        st['push'][(a['offset'], a['size'])] = self.blob(a['pValues']).hex() if isinstance(a.get('pValues'), str) else None

    def snapshot(self, cb, kind, point, args, cmd_index, record_index=None):
        st = self.state.get(cb)
        if st is None:
            return
        self.recordings.setdefault(cb, []).append({
            'kind': kind, 'cmd_index': cmd_index, 'pipeline': st['pipeline'].get(point),
            'sets': {k[1]: v for k, v in st['sets'].items() if k[0] == point},
            'push': {f'{o}:{s}': v for (o, s), v in st['push'].items()}, 'args': args, 'record_index': record_index})

    def on_vkCmdDraw(self, a):
        self.snapshot(a['commandBuffer'], 'draw', 'graphics', a, None, self.current_index)

    def on_vkCmdDrawIndexed(self, a):
        self.snapshot(a['commandBuffer'], 'draw_indexed', 'graphics', a, None, self.current_index)

    def on_vkCmdDispatch(self, a):
        self.snapshot(a['commandBuffer'], 'dispatch', 'compute', a, None, self.current_index)


def uniform_rows(capture, set_id, dynamic):
    """Each uniform binding of a bound set, resolved to float32 vec4 rows at this moment."""
    entry = capture.sets.get(set_id)
    if not entry:
        return {}
    layout = capture.set_layouts.get(entry['layout'], {})
    order = [b for b, (t, count) in sorted(layout.items()) if t in DYNAMIC_TYPES for _ in range(count)]
    dyn_for = {}
    for binding, offset in zip(order, dynamic):
        dyn_for.setdefault(binding, []).append(offset)
    out = {}
    for binding, slots in entry['bindings'].items():
        for element, (dtype, info) in slots.items():
            if dtype not in UNIFORM_TYPES or not isinstance(info, dict):
                continue
            extra = dyn_for.get(binding, [0])[min(element, len(dyn_for.get(binding, [0])) - 1)] if dtype in DYNAMIC_TYPES else 0
            size = info['range']
            buffer = capture.buffers.get(info['buffer'], {})
            if size == 18446744073709551615:
                size = buffer.get('size', 0) - info['offset']
            size = min(size, 65536)
            data = capture.read_buffer(info['buffer'], info['offset'] + extra, size)
            if data is None:
                continue
            count = len(data) // 16
            rows = [list(struct.unpack_from('<4f', data, 16 * i)) for i in range(count)]
            out[f'{binding}.{element}'] = {'buffer': info['buffer'], 'offset': info['offset'] + extra, 'size': size, 'rows': rows,
                                           'u32': [list(struct.unpack_from('<4I', data, 16 * i)) for i in range(count)]}
    return out


def sampled_images(capture, set_id):
    entry = capture.sets.get(set_id)
    out = {}
    if not entry:
        return out
    for binding, slots in entry['bindings'].items():
        for element, (dtype, info) in slots.items():
            if not isinstance(info, dict) or 'imageView' not in info:
                continue
            view = capture.views.get(info['imageView'], {})
            image = capture.images.get(view.get('image'), {})
            out[f'{binding}.{element}'] = {'view': info['imageView'], 'type': dtype, 'view_format': view.get('format'),
                                           'image_format': image.get('format'), 'extent': image.get('extent'),
                                           'components': view.get('components'), 'image': view.get('image')}
    return out


def run(jsonl: Path, out: Path):
    capture = Capture(jsonl.parent)
    out.mkdir(parents=True, exist_ok=False)
    draws = (out / 'draws.jsonl').open('w')
    executed = 0
    submit = 0
    with jsonl.open() as stream:
        for line in stream:
            record = json.loads(line)
            name = name_of(record)
            if name == 'vkQueueSubmit':
                args = record['function']['args']
                submits = args['pSubmits']
                for info in (submits if isinstance(submits, list) else [submits]):
                    if not info:
                        continue
                    for cb in info.get('pCommandBuffers') or []:
                        for i, draw in enumerate(capture.recordings.get(cb, [])):
                            pipeline = capture.pipelines.get(draw['pipeline'], {})
                            uniforms = {str(s): uniform_rows(capture, set_id, dyn) for s, (set_id, dyn) in draw['sets'].items()}
                            images = {str(s): sampled_images(capture, set_id) for s, (set_id, dyn) in draw['sets'].items()}
                            draws.write(json.dumps({'submit': submit, 'submit_index': record.get('index'), 'record_index': draw.get('record_index'),
                                                    'command_buffer': cb, 'ordinal': i, 'kind': draw['kind'],
                                                    'pipeline': draw['pipeline'], 'stages': pipeline.get('stages', {}),
                                                    'args': draw['args'], 'push': draw['push'], 'uniforms': uniforms, 'images': images}) + '\n')
                            executed += 1
                submit += 1
            capture.handle(record)
    draws.close()
    (out / 'modules.json').write_text(json.dumps(capture.modules, indent=1))
    (out / 'pipelines.json').write_text(json.dumps({str(k): v for k, v in capture.pipelines.items()}, indent=1))
    print(f'executed draws/dispatches: {executed}; submits: {submit}; modules: {len(capture.modules)}')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('jsonl', type=Path)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args(argv)
    run(args.jsonl, args.out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
