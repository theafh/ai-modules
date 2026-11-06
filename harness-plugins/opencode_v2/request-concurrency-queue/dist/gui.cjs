"use strict";Object.defineProperties(exports,{__esModule:{value:!0},[Symbol.toStringTag]:{value:"Module"}});const t=require("solid-js/web"),m=require("solid-js"),h=require("@opencode/plugin/gui"),T=`
.request-concurrency-status {
  display: flex;
  flex-direction: column;
  gap: 2px;
  padding: 8px 4px 12px;
  font-size: 12px;
  line-height: 1.45;
}

.request-concurrency-status-unavailable {
  padding: 8px 4px;
  font-style: italic;
  opacity: 0.65;
}

.request-concurrency-status-header,
.request-concurrency-status-row {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 4.5em 4em 3.5em 3.5em;
  column-gap: 10px;
  align-items: baseline;
}

.request-concurrency-status-header {
  padding: 0 8px 4px;
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  opacity: 0.55;
}

.request-concurrency-status-header > :not(:first-child) {
  text-align: right;
}

.request-concurrency-status-row {
  padding: 4px 8px;
  border-left: 2px solid transparent;
  border-radius: 4px;
  background: rgba(127, 127, 127, 0.06);
}

.request-concurrency-status-provider {
  min-width: 0;
  overflow: hidden;
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.request-concurrency-status-active,
.request-concurrency-status-queued,
.request-concurrency-status-utilization,
.request-concurrency-status-demand {
  font-variant-numeric: tabular-nums;
  font-weight: 600;
  text-align: right;
  white-space: nowrap;
}

.request-concurrency-status-max {
  font-weight: 400;
  opacity: 0.5;
}

.request-concurrency-feed {
  display: flex;
  flex-direction: column;
  gap: 1px;
  max-height: 12em;
  margin-top: 10px;
  padding-top: 8px;
  border-top: 1px solid rgba(127, 127, 127, 0.25);
  overflow-y: auto;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 11px;
}

.request-concurrency-feed-title {
  padding: 0 4px 4px;
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  opacity: 0.55;
}

.request-concurrency-feed-row {
  display: grid;
  grid-template-columns: auto 5em minmax(0, 0.8fr) minmax(0, 1fr) auto;
  column-gap: 8px;
  align-items: baseline;
  padding: 2px 4px;
  border-radius: 3px;
}

.request-concurrency-feed-time {
  font-variant-numeric: tabular-nums;
  opacity: 0.6;
}

.request-concurrency-feed-kind {
  font-size: 9px;
  font-weight: 700;
  letter-spacing: 0.04em;
  text-align: right;
  text-transform: uppercase;
}

.request-concurrency-feed-kind.is-acquired {
  color: #4ade80;
}

.request-concurrency-feed-kind.is-queued {
  color: #fbbf24;
}

.request-concurrency-feed-kind.is-released {
  opacity: 0.55;
}

.request-concurrency-feed-kind.is-dequeued {
  color: #60a5fa;
}

.request-concurrency-feed-provider,
.request-concurrency-feed-session {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.request-concurrency-feed-session {
  opacity: 0.6;
}

.request-concurrency-feed-counts {
  text-align: right;
  white-space: nowrap;
  opacity: 0.75;
}
`,M={type:"object",properties:{providerID:{type:"string"},active:{type:"integer",minimum:0},queued:{type:"integer",minimum:0},max:{type:"integer",minimum:0},utilization:{type:"number",minimum:0,maximum:1},demand:{type:"number",minimum:0}},required:["providerID","active","queued","max","utilization","demand"],additionalProperties:!1},E={type:"object",properties:{timestamp:{type:"integer",minimum:0},providerID:{type:"string"},kind:{type:"string",enum:["acquired","queued","released","dequeued"]},sessionID:{type:"string"},active:{type:"integer",minimum:0},queued:{type:"integer",minimum:0}},required:["timestamp","providerID","kind","sessionID","active","queued"],additionalProperties:!1},C={type:"object",properties:{},additionalProperties:!1},L={id:"request-concurrency-queue",methods:{status:{input:C,output:{type:"object",properties:{providers:{type:"array",items:M},transitions:{type:"array",items:E}},required:["providers","transitions"],additionalProperties:!1}}},events:{changed:{schema:C}}},g=[{percent:0,hue:145,saturation:65,lightness:50},{percent:100,hue:48,saturation:95,lightness:55},{percent:200,hue:28,saturation:95,lightness:58},{percent:300,hue:0,saturation:80,lightness:62}];function D(e){const s=Number.isFinite(e)?Math.max(0,e):0,u=g[g.length-1];if(s>=u.percent)return _(u);for(let n=1;n<g.length;n+=1){const r=g[n-1],a=g[n];if(s>a.percent)continue;const o=(s-r.percent)/(a.percent-r.percent);return`hsl(${Math.round(q(r.hue,a.hue,o))} ${Math.round(q(r.saturation,a.saturation,o))}% ${Math.round(q(r.lightness,a.lightness,o))}%)`}return _(u)}function _(e){return`hsl(${e.hue} ${e.saturation}% ${e.lightness}%)`}function q(e,s,u){return e+(s-e)*u}const N=5e3;function R(e){return{providerID:e.providerID,active:e.active,queued:e.queued,max:e.max,utilization:A(e.utilization),demand:A(e.demand),utilizationColor:D(e.utilization*100),demandColor:D(e.demand*100)}}function O(e){return e.providers.map(R)}const U=20;function j(e,s=U){return e.transitions.slice(-s).reverse().map(B)}function B(e){return{time:V(e.timestamp),providerID:e.providerID,kind:e.kind,sessionID:e.sessionID,active:e.active,queued:e.queued}}function F(e,s,u={}){const n=e(),r=u.refetchIntervalMs??N;let a=!1,o=0;const l=async()=>{const p=++o;let c;try{c=await n.status({},H(u.directory))}catch{!a&&p===o&&s(null);return}!a&&p===o&&s(c)};l();const y=n.events.on("changed",()=>{l()}),d=setInterval(()=>{l()},r);return()=>{a=!0,clearInterval(d),y()}}function H(e){return e===void 0?void 0:{location:{directory:e}}}function A(e){return`${Math.round(e*100)}%`}function V(e){const s=new Date(e),u=n=>String(n).padStart(2,"0");return`${u(s.getHours())}:${u(s.getMinutes())}:${u(s.getSeconds())}`}var Y=t.template("<div class=request-concurrency-status-header aria-hidden=true><span>Provider</span><span>Active</span><span>Queued</span><span>Util</span><span>Demand"),J=t.template("<div class=request-concurrency-feed><div class=request-concurrency-feed-title>Recent activity"),Q=t.template("<div class=request-concurrency-status>"),G=t.template("<div class=request-concurrency-status-unavailable>Status unavailable"),K=t.template('<div class=request-concurrency-status-row><span class=request-concurrency-status-provider></span><span class=request-concurrency-status-active><span></span><span class=request-concurrency-status-max></span></span><span class=request-concurrency-status-queued></span><span class=request-concurrency-status-utilization title="Utilization: active / max"></span><span class=request-concurrency-status-demand title="Demand: (active + queued) / max">'),W=t.template("<div class=request-concurrency-feed-row><span class=request-concurrency-feed-time></span><span></span><span class=request-concurrency-feed-provider></span><span class=request-concurrency-feed-session></span><span class=request-concurrency-feed-counts>");const X={id:"status",title:"Concurrency",pinned:!0},Z="Status unavailable",ee={providers:[],transitions:[]};function z(e){return e===null?{unavailable:!0,rows:[],transitions:[]}:{unavailable:!1,rows:O(e),transitions:j(e)}}function P(e){const s=()=>z(e.snapshot);return(()=>{var u=Q();return t.insert(u,t.createComponent(m.Show,{get when(){return!s().unavailable},get fallback(){return G()},get children(){return[t.createComponent(m.Show,{get when(){return s().rows.length>0},get children(){return Y()}}),t.createComponent(m.For,{get each(){return s().rows},children:n=>(()=>{var r=K(),a=r.firstChild,o=a.nextSibling,l=o.firstChild,y=l.nextSibling,d=o.nextSibling,p=d.nextSibling,c=p.nextSibling;return t.insert(a,()=>n.providerID),t.insert(l,()=>n.active),t.insert(y,()=>` / ${n.max}`),t.insert(d,()=>n.queued),t.insert(p,()=>n.utilization),t.insert(c,()=>n.demand),t.effect(i=>{var v=n.demandColor,f=n.providerID,x=`${n.active} of ${n.max} slots in use`,b=n.utilizationColor,S=n.demandColor,w=`${n.queued} waiting`,$=n.utilizationColor,I=n.demandColor;return v!==i.e&&t.setStyleProperty(r,"border-left-color",i.e=v),f!==i.t&&t.setAttribute(a,"title",i.t=f),x!==i.a&&t.setAttribute(o,"title",i.a=x),b!==i.o&&t.setStyleProperty(l,"color",i.o=b),S!==i.i&&t.setStyleProperty(d,"color",i.i=S),w!==i.n&&t.setAttribute(d,"title",i.n=w),$!==i.s&&t.setStyleProperty(p,"color",i.s=$),I!==i.h&&t.setStyleProperty(c,"color",i.h=I),i},{e:void 0,t:void 0,a:void 0,o:void 0,i:void 0,n:void 0,s:void 0,h:void 0}),r})()}),t.createComponent(m.Show,{get when(){return s().transitions.length>0},get children(){var n=J();return n.firstChild,t.insert(n,t.createComponent(m.For,{get each(){return s().transitions},children:r=>(()=>{var a=W(),o=a.firstChild,l=o.nextSibling,y=l.nextSibling,d=y.nextSibling,p=d.nextSibling;return t.insert(o,()=>r.time),t.insert(l,()=>r.kind),t.insert(y,()=>r.providerID),t.insert(d,()=>r.sessionID),t.insert(p,()=>`${r.active} active · ${r.queued} queued`),t.effect(c=>{var i=`request-concurrency-feed-kind is-${r.kind}`,v=r.providerID,f=r.sessionID;return i!==c.e&&t.className(l,c.e=i),v!==c.t&&t.setAttribute(y,"title",c.t=v),f!==c.a&&t.setAttribute(d,"title",c.a=f),c},{e:void 0,t:void 0,a:void 0}),a})()}),null),n}})]}})),u})()}function te(e){const[s,u]=m.createSignal(ee);return m.createEffect(()=>{const n=e.session.server.client,r=e.session.directory,a=F(()=>n.rpc(L),o=>u(o),{directory:r});m.onCleanup(a)}),t.createComponent(P,{get snapshot(){return s()}})}const k={id:"status",region:"side",list:()=>[X],render:e=>t.createComponent(te,{get tab(){return e.tab},get session(){return e.session},get screen(){return e.screen}})},ne=h.Plugin.define({setup(e){e.add(h.Panel,k),e.add(h.Style,T)}});exports.STATUS_UNAVAILABLE=Z;exports.StatusBody=P;exports.default=ne;exports.panel=k;exports.statusBodyState=z;
