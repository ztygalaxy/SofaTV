"""Build the vendored CCTV H5E decoder with a bounded, serialized macOS C ABI."""
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
src = root / 'vendor/cjs-main/sites/tv.cctv.com/native'
source = (src / 'cctv_h5e_decryptor.c').read_text()
source = source[:source.index('JNIEXPORT jbyteArray JNICALL')]
source = source.replace('#include <jni.h>', '').replace('#include <android/log.h>', '')
for level in ['I', 'W', 'E']:
    source = re.sub(r'#define LOG' + level + r'\(\.\.\.\).*', '#define LOG' + level + '(...) ((void)0)', source)
# GCD serial queues can migrate between OS threads. The ABI mutex owns one state
# allocation, and the upstream decoder already restarts it for every TS segment.
source = source.replace('static __thread ', 'static ')
# A TS access unit cannot grow past its original capacity. Reject a malformed
# WASM result before it can overflow the host PES reconstruction buffer.
source = source.replace('if (output_length > nal_length + host_length + NAL_MEMORY_EXTEND) {',
                        'if (output_length > nal_length) { g_decrypt_cancelled = 1;')
start = source.index('static int write_pes_payload(')
end = source.index('static int decrypt_pes(', start)
source = source[:start] + '#include "h5e-pes-writer.h"\n\n' + source[end:]
out = root / 'native/h5e'
out.mkdir(parents=True, exist_ok=True)
(out / 'h5e_macos.c').write_text(source)
subprocess.run([
    'clang', '-dynamiclib', '-mmacosx-version-min=14.0', '-O2', '-std=c99', '-DWASM_RT_USE_MMAP=0',
    '-I' + str(src), '-I' + str(src / 'generated'), '-I' + str(src / 'wasm-rt'),
    '-I' + str(root / 'scripts'), str(out / 'bridge.c'),
    str(src / 'generated/cctv_h5e_wasm.c'), str(src / 'wasm-rt/wasm-rt-impl.c'),
    str(src / 'wasm-rt/wasm-rt-mem-impl.c'), '-o', str(out / 'libSofaTVH5e.dylib')
], check=True)
print('Built macOS CCTV H5E runtime')
