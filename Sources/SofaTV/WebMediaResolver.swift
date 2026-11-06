import SwiftUI
import WebKit

/// Keeps a real, window-attached WebKit session behind the opaque native player.
/// No page UI is exposed and its media is always muted.
@MainActor final class WebMediaResolver: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    private(set) var cmgState: CmgSessionState?
    private var lastMedia: String?
    let webView: WKWebView
    private var generation = UUID()
    private var completion: ((URL, [HTTPCookie]) -> Void)?
    private var failure: ((String) -> Void)?
    private var candidates = Set<String>()
    private var active = false
    private var videoCompletion: ((Bool) -> Void)?
    private var preparingVideo = false
    private var desiredVolume: Float = 0.3
    private var pendingVolume: Float?
    private var volumeTask: Task<Void, Never>?
    override init() {
        let configuration = WKWebViewConfiguration()
        // Channel resolution only needs cookies for the current playback session.
        // A non-persistent store also prevents ad-hoc development builds from
        // touching WebKit data created under a previous code-signing identity.
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        configuration.userContentController.add(WeakMediaHandler(self), name: "media")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        webView.navigationDelegate = self
    }
    func resolve(_ url: URL, completion: @escaping (URL, [HTTPCookie]) -> Void, failure: @escaping (String) -> Void) {
        cancel(); active = true; candidates = []; self.completion = completion; self.failure = failure
        webView.load(URLRequest(url: url))
    }
    func showVideoOnly(completion: @escaping (Bool) -> Void) {
        videoCompletion = completion
        if !webView.isLoading, let scheme = webView.url?.scheme, ["http", "https"].contains(scheme) { prepareVideo() }
    }
    private func prepareVideo() {
        guard active, !preparingVideo, videoCompletion != nil else { return }
        preparingVideo = true
        let token = generation
        let script = #"""
        (async () => {
          window.__sofatvVideoOnly=true;window.__sofatvNativeActive=false;
          const style=document.createElement('style');style.id='__sofatvVideoStyle';
          style.textContent='video::-webkit-media-controls{display:none!important}html,body{background:black!important;overflow:hidden!important}body *{visibility:hidden!important}video[data-sofatv-selected]{visibility:visible!important;position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;object-fit:contain!important;z-index:2147483647!important;background:black!important}';
          document.documentElement.appendChild(style);
          const v=await new Promise(resolve=>{
            const timer=setInterval(()=>{const videos=[...document.querySelectorAll('video')];const v=videos.sort((a,b)=>(b.videoWidth*b.videoHeight)-(a.videoWidth*a.videoHeight))[0];if(v){clearInterval(timer);resolve(v);}},100);
            setTimeout(()=>{clearInterval(timer);resolve(null);},25000);
          });
          if(!v)return false;
          window.__sofatvSelectedVideo=v;v.setAttribute("data-sofatv-selected","true");
          v.muted=true;v.controls=false;v.removeAttribute("controls");v.playsInline=true;
          try{await v.play();}catch(_){}
          return await new Promise(resolve=>{
            let done=false;
            const finish=ok=>{if(done)return;done=true;resolve(ok);};
            const timer=setInterval(()=>{if(v.videoWidth>0&&v.readyState>=2){clearInterval(timer);finish(true);}},100);
            setTimeout(()=>{clearInterval(timer);finish(false);},25000);
          });
        })()
        """#
        Task { @MainActor in
            do {
                let value = try await webView.callAsyncJavaScript("return await " + script, arguments: [:], in: nil, contentWorld: .page)
                guard generation == token else { return }
                videoCompletion?(value as? Bool == true); videoCompletion = nil
            } catch {
                guard generation == token else { return }
                videoCompletion?(false); videoCompletion = nil
            }
        }
    }
    func setAudible(_ audible: Bool, volume: Float? = nil, completion: (() -> Void)? = nil) {
        let token = generation
        if let volume, volume.isFinite { desiredVolume = min(1, max(0, volume)) }
        Task { @MainActor in
            guard generation == token else { return }
            // Read the latest level at execution time so queued playback activation cannot undo user mute.
            let script = "window.__sofatvVolume=\(desiredVolume);window.__sofatvAudible=\(audible ? "true" : "false");document.querySelectorAll('video,audio').forEach(v=>{v.volume=window.__sofatvVolume;v.muted=!window.__sofatvAudible || v!==window.__sofatvSelectedVideo;});"
            do { _ = try await webView.evaluateJavaScript(script) }
            catch { if !audible, generation == token { await webView.pauseAllMediaPlayback() } }
            guard generation == token else { return }
            completion?()
        }
    }
    func setVolume(_ volume: Float) {
        guard volume.isFinite else { return }
        let level = min(1, max(0, volume))
        desiredVolume = level
        if level == 0 { volumeTask?.cancel(); volumeTask = nil }
        pendingVolume = level
        guard volumeTask == nil else { return }
        let token = generation
        // Mute immediately; combine continuous nonzero changes rather than queueing every input event.
        volumeTask = Task { @MainActor [weak self] in
            var waitBeforeSending = level != 0
            while !Task.isCancelled {
                if waitBeforeSending {
                    do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                }
                waitBeforeSending = true
                guard let self, self.generation == token, !Task.isCancelled else { return }
                guard let level = self.pendingVolume else { self.volumeTask = nil; return }
                self.pendingVolume = nil
                _ = try? await self.webView.evaluateJavaScript("window.__sofatvVolume=\(level);document.querySelectorAll('video,audio').forEach(v=>v.volume=window.__sofatvVolume);")
                guard self.generation == token, !Task.isCancelled else { return }
                if self.pendingVolume == nil { self.volumeTask = nil; return }
            }
        }
    }
    /// After native takeover, keep the page/session but stop duplicate video decoding.
    func suspendVideoForNative() {
        let token = generation
        Task { @MainActor in
            guard generation == token else { return }
            _ = try? await webView.evaluateJavaScript("window.__sofatvNativeActive=true;window.__sofatvAudible=false;document.querySelectorAll('video,audio').forEach(v=>{v.muted=true;v.pause();});")
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { prepareVideo() }
    func cancel() {
        volumeTask?.cancel(); volumeTask = nil; pendingVolume = nil
        videoCompletion = nil; preparingVideo = false
        cmgState = nil; lastMedia = nil
        active = false; generation = UUID(); completion = nil; failure = nil
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if active, let state = message.body as? [String: Any], let tag = state["tag"] as? String, !tag.isEmpty {
            cmgState = CmgSessionState(tag: tag, location: state["location"] as? String ?? "https://www.yangshipin.cn/tv/home", timestamp: UInt64((state["timestamp"] as? Double) ?? 0), nativeTrace: state["trace"] as? String ?? "", updates: state["updates"] as? String ?? "", base: UInt64((state["base"] as? Double) ?? 0))
            if let value = lastMedia { candidates.remove(value); deliver(value) }
            return
        }
        guard active, let value = message.body as? String else { return }
        deliver(value)
    }
    private func deliver(_ value: String) {
        guard active, let url = URL(string: value),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              candidates.insert(value).inserted else { return }
        lastMedia = value
        let token = generation
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self, self.active, self.generation == token else { return }
            self.completion?(url, cookies)
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard active, (error as NSError).code != NSURLErrorCancelled else { return }
        failure?("频道网页加载失败：" + error.localizedDescription)
    }
    private static let script = #"""
    (() => {
      // Observe the same CMG exports used by the upstream JNI implementation.
      if (window.WebAssembly) {
        const instrument = (instance, imports) => {
          const e = instance.exports;
          if (!e.ba || !e.da || !e.Ca || !e.Ba || !e.ea || !imports?.env?.memory) return instance;
          const mem = imports.env.memory; let tag='', timestamp=0, base=0, sent=false;
          const trace=[], updates=[];
          const names={ba:'_CMG_InitPlayer',da:'_CMG_UpdatePlayer',Ca:'_jsmalloc',Ba:'_jsfree'};
          const wrapped = {};
          for (const key of Object.keys(e)) {
            const fn=e[key];
            if (typeof fn !== 'function' || !names[key]) { wrapped[key]=fn; continue; }
            wrapped[key]=function(...args) {
              const now=Date.now();
              if (key==='ba') { const a=new Uint8Array(mem.buffer); let p=args[0], s='';while(p<a.length && a[p] && s.length<128)s+=String.fromCharCode(a[p++]);tag=s;timestamp=now; }
              const r=fn(...args);
              if(trace.length<128)trace.push(names[key]+':'+args.join(',')+'->'+r);
              if(key==='da') { if(!base)base=now;if(updates.length<96)updates.push((now-base)+','+r); }
              if(tag && base && !sent) { sent=true;setTimeout(()=>window.webkit.messageHandlers.media.postMessage({tag, timestamp, base, location:location.href, trace:trace.join(';'),updates:updates.join(';')}),0); }
              return r;
            };
          }
          const result=Object.create(instance);Object.defineProperty(result,'exports',{value:wrapped});return result;
        };
        const original=WebAssembly.instantiate;
        WebAssembly.instantiate=function(source, imports) { return original.call(this,source,imports).then(result => result.instance ? {module:result.module,instance:instrument(result.instance,imports)} : instrument(result,imports)); };
        const streaming=WebAssembly.instantiateStreaming;
        if(streaming)WebAssembly.instantiateStreaming=function(response, imports) { return streaming.call(this,response,imports).then(result=>({module:result.module,instance:instrument(result.instance,imports)})); };
      }
      const seen = new Set();
      const send = value => {
        try {
          const u = new URL(value, location.href);
          if (!/^https?:$/.test(u.protocol) || !(/\.(m3u8|mp4|m4v|mov|mp3|aac)([?#]|$)/i.test(u.href))) return;
          if (!seen.has(u.href)) { seen.add(u.href); window.webkit.messageHandlers.media.postMessage(u.href); }
        } catch (_) {}
      };
      const scanObject = (obj, depth = 0) => {
        if (depth > 6 || !obj) return;
        if (typeof obj === 'string') { send(obj); return; }
        if (typeof obj === 'object') Object.values(obj).slice(0, 200).forEach(x => scanObject(x, depth + 1));
      };
      const fetchOriginal = window.fetch;
      if (fetchOriginal) window.fetch = function(...args) {
        send(args[0] instanceof Request ? args[0].url : args[0]);
        return fetchOriginal.apply(this, args).then(r => {
          send(r.url);
          if ((r.headers.get('content-type') || '').includes('json')) r.clone().json().then(scanObject).catch(() => {});
          return r;
        });
      };
      const openOriginal = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url, ...rest) {
        send(url);
        this.addEventListener('load', () => {
          send(this.responseURL);
          try { if (this.responseType === 'json') scanObject(this.response); else if (!this.responseType || this.responseType === 'text') scanObject(JSON.parse(this.responseText)); } catch (_) {}
        });
        return openOriginal.call(this, method, url, ...rest);
      };
      try { new PerformanceObserver(list => list.getEntries().forEach(e => send(e.name))).observe({entryTypes:['resource']}); } catch (_) {}
      const scan = () => {
        document.querySelectorAll('video,audio').forEach(v => {
          if (window.__sofatvVideoOnly) {
            let style = document.getElementById('__sofatvVideoStyle');
            if (!style) { const s=document.createElement('style');s.id='__sofatvVideoStyle';s.textContent='video::-webkit-media-controls{display:none!important}html,body{background:black!important;overflow:hidden!important}body *{visibility:hidden!important}video[data-sofatv-selected]{visibility:visible!important;position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;object-fit:contain!important;z-index:2147483647!important;background:black!important}';document.documentElement.appendChild(s); }
            if (window.__sofatvVolume !== undefined) v.volume = window.__sofatvVolume;
            v.muted = !window.__sofatvAudible || v !== window.__sofatvSelectedVideo; v.controls = false; v.removeAttribute("controls");
          } else { v.muted = true; v.volume = 0; }
          send(v.currentSrc); send(v.src);
          v.querySelectorAll('source').forEach(s => send(s.src));
          if (window.__sofatvNativeActive) { if (!v.paused) v.pause(); }
          else if (v.paused) { try { const p = v.play(); if (p) p.catch(() => {}); } catch (_) {} }
        });
        performance.getEntriesByType('resource').forEach(e => send(e.name));
      };
      setInterval(scan, 1000);
      document.addEventListener('DOMContentLoaded', scan);
    })();
    """#
}
@MainActor private final class WeakMediaHandler: NSObject, WKScriptMessageHandler {
    weak var target: WebMediaResolver?
    init(_ target: WebMediaResolver) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) { target?.userContentController(controller, didReceive: message) }
}
struct ResolverHost: NSViewRepresentable {
    let resolver: WebMediaResolver
    func makeNSView(context: Context) -> WKWebView { resolver.webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
