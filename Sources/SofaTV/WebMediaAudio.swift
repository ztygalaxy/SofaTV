import Foundation

/// Install before page scripts: a site's saved/default volume must never bypass
/// the app's level, including media created before DOMContentLoaded or in frames.
enum WebMediaAudio {
    static let script = #"""
    (() => {
      window.__sofatvAudible=false;
      window.__sofatvVolume=0;
      const prototype=window.HTMLMediaElement?.prototype;
      if(!prototype)return;
      const volume=Object.getOwnPropertyDescriptor(prototype,'volume');
      const muted=Object.getOwnPropertyDescriptor(prototype,'muted');
      if(!volume?.get || !volume?.set || !muted?.get || !muted?.set)return;
      const apply=media=>{
        if(!(media instanceof HTMLMediaElement))return;
        const level=Number.isFinite(window.__sofatvVolume)?Math.min(1,Math.max(0,window.__sofatvVolume)):0;
        const audible=window.__sofatvAudible===true && !window.__sofatvNativeActive &&
                      media===window.__sofatvSelectedVideo && level>0;
        // Set the gain before releasing mute; do not toggle unchanged properties
        // or volumechange would continuously trigger itself.
        if(!audible && !muted.get.call(media))muted.set.call(media,true);
        const target=audible?level:0;
        if(volume.get.call(media)!==target)volume.set.call(media,target);
        if(audible && muted.get.call(media))muted.set.call(media,false);
      };
      window.__sofatvApplyAudio=apply;
      for(const [name,descriptor] of [['volume',volume],['muted',muted]]) {
        Object.defineProperty(prototype,name,{configurable:descriptor.configurable,
          enumerable:descriptor.enumerable,get:descriptor.get,set(){apply(this);}});
      }
      const play=prototype.play;
      prototype.play=function(...args){apply(this);return play.apply(this,args);};
      document.addEventListener('play',event=>apply(event.target),true);
      document.addEventListener('volumechange',event=>apply(event.target),true);
      const scan=node=>{
        apply(node);
        node.querySelectorAll?.('video,audio').forEach(apply);
      };
      new MutationObserver(records=>records.forEach(record=>{
        if(record.type==='attributes')apply(record.target);
        else record.addedNodes.forEach(scan);
      })).observe(document,{childList:true,subtree:true,attributes:true,attributeFilter:['muted']});
      document.addEventListener('DOMContentLoaded',()=>scan(document));
    })();
    """#
}
