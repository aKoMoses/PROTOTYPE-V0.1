"""Validate the actual standalone GLB bytes, not the exporter success message."""
from pathlib import Path
import json
import math
import struct
import hashlib

ROOT = Path(__file__).resolve().parent.parent
IDS = ('pyro_boots', 'bio_injector', 'rocket_basket', 'magnetic_field', 'auxiliary_reactor')


def inspect(identifier):
    path = ROOT / 'art' / 'modules' / (identifier + '.glb')
    data = path.read_bytes()
    magic, version, length = struct.unpack_from('<III', data)
    assert magic == 0x46546C67 and version == 2 and length == len(data), 'GLB header/length'
    jl, jt = struct.unpack_from('<II', data, 12)
    assert jt == 0x4E4F534A
    doc = json.loads(data[20:20+jl])
    start = 20+jl
    bl, bt = struct.unpack_from('<II', data, start)
    assert bt == 0x004E4942 and start+8+bl == len(data)
    binary = data[start+8:]
    assert all('uri' not in image and image.get('mimeType') == 'image/png' for image in doc['images'])
    assert all(mat.get('alphaMode', 'OPAQUE') == 'OPAQUE' for mat in doc['materials'])
    assert len(doc['meshes']) <= 10 and len(doc['materials']) <= 10
    assert len(doc.get('animations', [])) == 0 and len(doc.get('skins', [])) == 0

    def array(index):
        accessor = doc['accessors'][index]
        view = doc['bufferViews'][accessor['bufferView']]
        kinds = {5120: 'b', 5121: 'B', 5122: 'h', 5123: 'H', 5125: 'I', 5126: 'f'}
        widths = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}
        fmt = '<' + kinds[accessor['componentType']] * widths[accessor['type']]
        size = struct.calcsize(fmt)
        step = view.get('byteStride', size)
        begin = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
        assert begin+(accessor['count']-1)*step+size <= len(binary)
        return [struct.unpack_from(fmt, binary, begin+i*step) for i in range(accessor['count'])]

    triangles = vertices = 0
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            attributes = primitive['attributes']
            assert all(key in attributes for key in ('POSITION', 'NORMAL', 'TEXCOORD_0'))
            points = array(attributes['POSITION'])
            normals = array(attributes['NORMAL'])
            uv = array(attributes['TEXCOORD_0'])
            assert all(math.isfinite(x) for p in points+normals+uv for x in p)
            assert all(.96 < sum(x*x for x in n) < 1.04 for n in normals), 'unit normals'
            indices = [x[0] for x in array(primitive['indices'])]
            assert len(indices) % 3 == 0 and min(indices) >= 0 and max(indices) < len(points)
            assert len(set(indices)) == len(points), 'all geometry indexed'
            for offset in range(0, len(indices), 3):
                assert len(set(indices[offset:offset+3])) == 3, 'collapsed index triangle'
            vertices += len(points)
            triangles += len(indices)//3
    assert 1000 <= triangles <= 25000
    report = {'asset': identifier, 'triangles': triangles, 'vertices': vertices,
              'materials': len(doc['materials']), 'embedded_images': len(doc['images']),
              'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    manifest = json.loads(path.with_suffix('.asset.json').read_text())
    assert report['sha256'] == manifest['sha256'] and triangles == manifest['triangles']
    print(json.dumps(report), flush=True)
    return report


if __name__ == '__main__':
    result = [inspect(identifier) for identifier in IDS]
    total = sum(item['triangles'] for item in result if item['asset'] not in ('pyro_boots', 'bio_injector'))
    kit = max(result[0]['triangles']*2, result[1]['triangles']) + total
    assert kit <= 60000, 'equipped accessory geometry budget'
    print('MODULE GLB INSPECTION: PASS, max equipped accessory triangles=' + str(kit))
