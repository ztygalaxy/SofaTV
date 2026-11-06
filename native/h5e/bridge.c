/* macOS ABI around the vendored H5E implementation; generated WASM is unchanged. */
#include "h5e_macos.c"

static pthread_mutex_t sofatv_h5e_lock = PTHREAD_MUTEX_INITIALIZER;

static void sofatv_h5e_reset_locked(void) {
    if (g_runtime_initialized) {
        reset_emval_state();
        wasm2c_cctv__h5e_free(&g_module);
        wasm_rt_free_funcref_table(&g_env.table);
        wasm_rt_free_memory(&g_env.memory);
    }
    memset(&g_env, 0, sizeof(g_env));
    memset(&g_module, 0, sizeof(g_module));
    g_runtime_initialized = 0;
    g_ready = 0;
    g_session_started = 0;
    g_should_decrypt = 0;
    g_worker_clock_frozen = 0;
    g_wasm_stage = "idle";
}

int32_t sofatv_h5e_decode(uint8_t* bytes, int32_t length) {
    if (!bytes || length <= 0 || length > 32 * 1024 * 1024 || length % TS_PACKET_SIZE) return -1;
    for (int32_t offset = 0; offset < length; offset += TS_PACKET_SIZE) {
        if (bytes[offset] != 0x47) return -1;
    }
    pthread_mutex_lock(&sofatv_h5e_lock);
    g_decrypt_generation = __sync_add_and_fetch(&g_cancel_generation, 0);
    g_decrypt_cancelled = 0;
    int32_t result;
    wasm_rt_trap_t trap = (wasm_rt_trap_t) wasm_rt_try(g_wasm_rt_jmp_buf);
    if (trap == WASM_RT_TRAP_NONE) {
        result = decrypt_transport_stream(bytes, bytes, (size_t)length) ? length : -3;
    } else {
        g_ready = 0;
        g_session_started = 0;
        g_worker_clock_frozen = 0;
        result = -2;
    }
    if (g_decrypt_cancelled) result = -4;
    if (result < 0) sofatv_h5e_reset_locked();
    pthread_mutex_unlock(&sofatv_h5e_lock);
    return result;
}

void sofatv_h5e_reset(void) {
    pthread_mutex_lock(&sofatv_h5e_lock);
    sofatv_h5e_reset_locked();
    pthread_mutex_unlock(&sofatv_h5e_lock);
}

__attribute__((destructor)) static void sofatv_h5e_unload(void) {
    sofatv_h5e_reset();
}
