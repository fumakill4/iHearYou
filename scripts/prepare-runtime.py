#!/usr/bin/env python3
# iHearYou | Signature: i729
from pathlib import Path
import hashlib
import io
import tarfile
import urllib.request

root = Path(__file__).resolve().parents[1]
model = root / 'Vendor/DPDFNet/dpdfnet2_48khz_hr.onnx'
model_hash = '0b399f8a58dc4d70d8cd97541f5c39869406145193b957d00a03b66070944928'
archive_hash = 'f3e0cbd86cc3f38dad30c97921b40e9a8bcc6f2c943777eb76ad77176993e417'

def digest(data): return hashlib.sha256(data).hexdigest()
def download(url, expected):
    with urllib.request.urlopen(url, timeout=60) as response: data = response.read()
    if digest(data) != expected: raise RuntimeError('Checksum mismatch: ' + url)
    return data

if not model.exists() or digest(model.read_bytes()) != model_hash:
    data = download('https://github.com/k2-fsa/sherpa-onnx/releases/download/speech-enhancement-models/dpdfnet2_48khz_hr.onnx', model_hash)
    model.parent.mkdir(parents=True, exist_ok=True); model.write_bytes(data)
runtime = root / 'Vendor/Sherpa/lib'
needed = {
    'libsherpa-onnx-c-api.dylib': 'ae729669633008692c670d4e4c942db7ea5bdc38abc2f479516062d48849e9d1',
    'libonnxruntime.dylib': '3567d114f7299d559993e536d605a6f46d7bc9d2542004accc80ee9bf5457f0b',
}
if any(not (runtime / name).exists() or digest((runtime / name).read_bytes()) != checksum
       for name, checksum in needed.items()):
    data = download('https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/sherpa-onnx-v1.13.8-osx-arm64-shared-no-tts-lib.tar.bz2', archive_hash)
    runtime.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:bz2') as archive:
        for name, checksum in needed.items():
            member = next(m for m in archive.getmembers() if m.isfile() and m.name.endswith('/lib/' + name))
            library = archive.extractfile(member).read()
            if digest(library) != checksum: raise RuntimeError('Runtime checksum mismatch: ' + name)
            (runtime / name).write_bytes(library)
print('Verified DPDFNet2 48 kHz model; sherpa-onnx 1.13.8 runtime ready.')
