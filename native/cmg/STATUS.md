# CMG macOS port

Sources: `vendor/cjs-main/sites/yangshipin.cn/native` and NativeWasmTv `HlsProxyServer` / `PesBuffer`. `scripts/build-cmg-macos.py` adapts JNI to a C ABI and builds the bundled macOS library.

Connected: browser CMG session/tag observation, loopback-only HLS delivery, TS/PES/NAL transform with length-changing repacking and adaptation-field preservation, native first-frame detection, and web/native arbitration. Native takeover pauses duplicate browser media decoding while preserving the page/session.

Long-play corrections: restart native state for every TS segment; refresh at the next SPS after 150 VCLs; use captured stable tags if an update returns zero; hold one process-wide lock for a complete segment so old-channel downloads cannot overwrite current-channel state; coalesce duplicate downloads; use a bounded LRU cache and rolling route map. Removed per-byte integer offset arrays from PES buffering. Build uses Release optimization.

Checks passed: playlist/PES checks; simulated 5,100 VCLs across 30 segments with boundary refresh; old/new channel isolation; LRU limits; playback arbitration. Real native library: 100 initialize/reset cycles, about 16.6 MiB peak RSS growth in the test process. Several channels produced native frames. Actual Hainan diagnostics included a 220-frame segment with one boundary refresh; user reported improved long-play behavior on 2026-11-06.

Outstanding: encrypted-fixture comparison against Android, broader channel and extended uninterrupted playback coverage, and sample-accurate live-edge alignment during handoff. Concurrent user channel switching prevented treating the development observation period as one uninterrupted soak test.
