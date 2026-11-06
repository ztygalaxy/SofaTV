"""Build the upstream CMG runtime with a macOS C interface instead of JNI."""
from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[1]
src = root / 'vendor/cjs-main/sites/yangshipin.cn/native'
text = (src/'cmg_decryptor.c').read_text()
core = text[:text.index('JNIEXPORT jstring JNICALL')]
core = core.replace('#include <jni.h>', '').replace('#include <android/log.h>', '')
for level in ['I', 'W', 'E']:
    import re
    core = re.sub(r'#define LOG'+level+r'\(\.\.\.\).*', '#define LOG'+level+'(...) ((void)0)', core)
function = text[text.index('JNIEXPORT jint JNICALL\nJava_com_bu_cc_tv_NativeCmgDecryptor_decodeNalRangeInPlace'):text.index('JNIEXPORT jbyteArray JNICALL\nJava_com_bu_cc_tv_NativeCmgDecryptor_decodeNalSingleStep')]
start = function.index('  pthread_mutex_lock(&g_lock);')
function = 'int sofatv_cmg_decode(uint8_t *input_bytes, int length, int live, int run_steps) {\n' + function[function.index('  u32 data_address;'):function.index('  (void) clazz;')] + '\nif (!input_bytes || length <= 0) return -1;\n' + function[start:]
function = function.replace('  jbyte* input_bytes;\n','').replace('input_bytes + offset','input_bytes').replace('return (jint) result;', 'return result;')
function = re.sub(r'\s*\(\*env\)->ReleaseByteArrayElements\(env, input, input_bytes,\s*(?:JNI_ABORT|result >= 0 \? 0 : JNI_ABORT)\);', '', function)
bridge = '''
void sofatv_cmg_set_update_tag(unsigned tag) { pthread_mutex_lock(&g_lock);g_update_tag=tag;pthread_mutex_unlock(&g_lock); }

unsigned sofatv_cmg_update(void) { pthread_mutex_lock(&g_lock); unsigned result=0; if(cmg_init_locked() && g_player_active) { int trap=wasm_rt_impl_try(); if(!trap) { result=cmg_update_player_with_fresh_tag();g_update_tag=result; } } pthread_mutex_unlock(&g_lock);return result; }
void sofatv_cmg_clock(unsigned long long time) { pthread_mutex_lock(&g_lock);g_forced_clock_ms=time;pthread_mutex_unlock(&g_lock); }
unsigned sofatv_cmg_replay(const char *native, const char *updates, unsigned long long base, int offset) { pthread_mutex_lock(&g_lock);unsigned result=cmg_replay_official_trace_locked(native,updates,base,offset);if(result)g_update_tag=result;pthread_mutex_unlock(&g_lock);return result; }

int sofatv_cmg_initialize(const char *tag, const char *href, unsigned update_tag) {
 pthread_mutex_lock(&g_lock);
 cmg_reset_runtime_locked();
 snprintf(g_forced_player_tag,sizeof(g_forced_player_tag),"%s",tag ? tag : "");
 snprintf(g_forced_location_href,sizeof(g_forced_location_href),"%s",href ? href : CMG_LOCATION_HREF);
 g_update_tag=update_tag;
 int result=cmg_init_locked();
 if(g_player_init_trap != 0) result=0;
 pthread_mutex_unlock(&g_lock);
 return result;
}
void sofatv_cmg_reset(void) { pthread_mutex_lock(&g_lock); cmg_reset_runtime_locked(); pthread_mutex_unlock(&g_lock); }
'''
out=root/'native/cmg';out.mkdir(parents=True,exist_ok=True)
(out/'cmg_macos.c').write_text(core+bridge+function)
subprocess.run(['clang','-dynamiclib','-mmacosx-version-min=14.0','-O2','-std=c99','-DWASM_RT_MEMCHECK_SIGNAL_HANDLER=0', '-I'+str(src/'generated_cmg'),'-I'+str(src/'cmg-rt'),str(out/'cmg_macos.c'),str(src/'generated_cmg/cmg_wasm.c'),str(src/'cmg-rt/wasm-rt-impl.c'),'-o',str(out/'libSofaTVCmg.dylib')],check=True)
print('Built macOS CMG runtime')
