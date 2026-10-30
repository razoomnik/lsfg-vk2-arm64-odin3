#!/usr/bin/env python3
"""Validate a Decky archive without executing its plugin code."""
import hashlib
import json
from pathlib import Path
import struct
import sys
import zipfile

archive = Path(sys.argv[1])
root = Path(__file__).resolve().parent.parent / "plugin"
prefix = "decky-lsfg-vk2-arm64/"
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None, "ZIP CRC failure"
    files = {n for n in z.namelist() if not n.endswith("/")}
    expected = {prefix + p.relative_to(root).as_posix() for p in root.rglob("*")
                if p.is_file() and "__pycache__" not in p.parts and p.suffix != ".pyc"}
    assert files == expected, f"Unexpected/missing payload: {files ^ expected}"
    for name in files:
        assert z.read(name) == (root / name[len(prefix):]).read_bytes(), name
    package = json.loads(z.read(prefix + "package.json"))
    json.loads(z.read(prefix + "plugin.json"))
    lib = z.read(prefix + "bin/arm64-hot1x/liblsfg-vk-layer.so")
    assert lib[:6] == b"\x7fELF\x02\x01", "Expected ELF64 little-endian binary"
    assert struct.unpack_from("<H", lib, 18)[0] == 183, "Expected AArch64 binary"
    expected_hash = z.read(prefix + "bin/arm64-hot1x/liblsfg-vk-layer.so.sha256").decode().split()[0]
    assert hashlib.sha256(lib).hexdigest() == expected_hash, "Bundled Vulkan binary checksum mismatch"
    js = z.read(prefix + "dist/index.js").decode()
    assert '"flow-children": "horizontal"' not in js, "Obsolete focus direction"
    assert js.count('"flow-children": "row"') == 3, "Expected three corrected focus rows"
print(f"Validated {archive.name}: {len(files)} files, version {package['version']}, ARM64 payload intact")
