"use strict";Object.defineProperties(exports,{__esModule:{value:!0},[Symbol.toStringTag]:{value:"Module"}});const e=require("solid-js/web"),m=require("solid-js"),v=require("@opencode/plugin/gui"),N=`
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

.request-concurrency-bar {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 100%;
  min-width: 0;
  height: 28px;
  padding: 0 10px;
  border: 0;
  border-top: 1px solid rgba(127, 127, 127, 0.25);
  background: rgba(127, 127, 127, 0.06);
  color: inherit;
  font: inherit;
  font-size: 11px;
  text-align: left;
  cursor: pointer;
}

.request-concurrency-bar:hover {
  background: rgba(127, 127, 127, 0.12);
}

.request-concurrency-bar:focus-visible {
  outline: 2px solid currentColor;
  outline-offset: -2px;
}

.request-concurrency-bar::after {
  content: "›";
  margin-left: auto;
  font-size: 14px;
  line-height: 1;
  opacity: 0.4;
}

.request-concurrency-bar-label {
  flex: none;
  font-weight: 600;
  letter-spacing: 0.02em;
}

.request-concurrency-bar-items {
  display: flex;
  align-items: baseline;
  gap: 14px;
  min-width: 0;
  overflow: hidden;
}

.request-concurrency-bar-item {
  display: inline-flex;
  align-items: baseline;
  gap: 5px;
  white-space: nowrap;
}

.request-concurrency-bar-provider {
  opacity: 0.7;
}

.request-concurrency-bar-sep {
  opacity: 0.3;
}

.request-concurrency-bar-muted {
  font-style: italic;
  opacity: 0.6;
}

.request-concurrency-dialog .request-concurrency-status {
  padding: 0;
}
`,O={type:"object",properties:{providerID:{type:"string"},active:{type:"integer",minimum:0},queued:{type:"integer",minimum:0},max:{type:"integer",minimum:0},utilization:{type:"number",minimum:0,maximum:1},demand:{type:"number",minimum:0}},required:["providerID","active","queued","max","utilization","demand"],additionalProperties:!1},R={type:"object",properties:{timestamp:{type:"integer",minimum:0},providerID:{type:"string"},kind:{type:"string",enum:["acquired","queued","released","dequeued"]},sessionID:{type:"string"},active:{type:"integer",minimum:0},queued:{type:"integer",minimum:0}},required:["timestamp","providerID","kind","sessionID","active","queued"],additionalProperties:!1},D={type:"object",properties:{},additionalProperties:!1},k={id:"request-concurrency-queue",methods:{status:{input:D,output:{type:"object",properties:{providers:{type:"array",items:O},transitions:{type:"array",items:R}},required:["providers","transitions"],additionalProperties:!1}}},events:{changed:{schema:D}}},h=[{percent:0,hue:145,saturation:65,lightness:50},{percent:100,hue:48,saturation:95,lightness:55},{percent:200,hue:28,saturation:95,lightness:58},{percent:300,hue:0,saturation:80,lightness:62}];function A(t){const s=Number.isFinite(t)?Math.max(0,t):0,i=h[h.length-1];if(s>=i.percent)return z(i);for(let n=1;n<h.length;n+=1){const r=h[n-1],a=h[n];if(s>a.percent)continue;const c=(s-r.percent)/(a.percent-r.percent);return`hsl(${Math.round(b(r.hue,a.hue,c))} ${Math.round(b(r.saturation,a.saturation,c))}% ${Math.round(b(r.lightness,a.lightness,c))}%)`}return z(i)}function z(t){return`hsl(${t.hue} ${t.saturation}% ${t.lightness}%)`}function b(t,s,i){return t+(s-t)*i}const F=5e3;function U(t){return{providerID:t.providerID,active:t.active,queued:t.queued,max:t.max,utilization:P(t.utilization),demand:P(t.demand),utilizationColor:A(t.utilization*100),demandColor:A(t.demand*100)}}function j(t){return t.providers.map(U)}const H=20;function V(t,s=H){return t.transitions.slice(-s).reverse().map(Y)}function Y(t){return{time:Q(t.timestamp),providerID:t.providerID,kind:t.kind,sessionID:t.sessionID,active:t.active,queued:t.queued}}function T(t,s,i={}){const n=t(),r=i.refetchIntervalMs??F;let a=!1,c=0;const l=async()=>{const d=++c;let p;try{p=await n.status({},J(i.directory))}catch{!a&&d===c&&s(null);return}!a&&d===c&&s(p)};l();const g=n.events.on("changed",()=>{l()}),u=setInterval(()=>{l()},r);return()=>{a=!0,clearInterval(u),g()}}function J(t){return t===void 0?void 0:{location:{directory:t}}}function P(t){return`${Math.round(t*100)}%`}function Q(t){const s=new Date(t),i=n=>String(n).padStart(2,"0");return`${i(s.getHours())}:${i(s.getMinutes())}:${i(s.getSeconds())}`}var G=e.template("<div class=request-concurrency-status-header aria-hidden=true><span>Provider</span><span>Active</span><span>Queued</span><span>Util</span><span>Demand"),K=e.template("<div class=request-concurrency-feed><div class=request-concurrency-feed-title>Recent activity"),W=e.template("<div class=request-concurrency-status>"),X=e.template("<div class=request-concurrency-status-unavailable>Status unavailable"),Z=e.template('<div class=request-concurrency-status-row><span class=request-concurrency-status-provider></span><span class=request-concurrency-status-active><span></span><span class=request-concurrency-status-max></span></span><span class=request-concurrency-status-queued></span><span class=request-concurrency-status-utilization title="Utilization: active / max"></span><span class=request-concurrency-status-demand title="Demand: (active + queued) / max">'),ee=e.template("<div class=request-concurrency-feed-row><span class=request-concurrency-feed-time></span><span></span><span class=request-concurrency-feed-provider></span><span class=request-concurrency-feed-session></span><span class=request-concurrency-feed-counts>"),te=e.template("<span class=request-concurrency-bar-items>"),ne=e.template('<button type=button class=request-concurrency-bar title="Open concurrency details"aria-label="Open concurrency details"><span class=request-concurrency-bar-label>Concurrency'),re=e.template("<span class=request-concurrency-bar-muted>Status unavailable"),se=e.template("<span class=request-concurrency-bar-item><span class=request-concurrency-bar-provider></span><span></span><span class=request-concurrency-bar-sep aria-hidden=true>·</span><span>"),ie=e.template("<div class=request-concurrency-dialog>");const ae={id:"status",title:"Concurrency",pinned:!0},oe="Status unavailable",M={providers:[],transitions:[]};function q(t){return t===null?{unavailable:!0,rows:[],transitions:[]}:{unavailable:!1,rows:j(t),transitions:V(t)}}function x(t){const s=()=>q(t.snapshot);return(()=>{var i=W();return e.insert(i,e.createComponent(m.Show,{get when(){return!s().unavailable},get fallback(){return X()},get children(){return[e.createComponent(m.Show,{get when(){return s().rows.length>0},get children(){return G()}}),e.createComponent(m.For,{get each(){return s().rows},children:n=>(()=>{var r=Z(),a=r.firstChild,c=a.nextSibling,l=c.firstChild,g=l.nextSibling,u=c.nextSibling,d=u.nextSibling,p=d.nextSibling;return e.insert(a,()=>n.providerID),e.insert(l,()=>n.active),e.insert(g,()=>` / ${n.max}`),e.insert(u,()=>n.queued),e.insert(d,()=>n.utilization),e.insert(p,()=>n.demand),e.effect(o=>{var y=n.demandColor,f=n.providerID,S=`${n.active} of ${n.max} slots in use`,$=n.utilizationColor,w=n.demandColor,C=`${n.queued} waiting`,_=n.utilizationColor,I=n.demandColor;return y!==o.e&&e.setStyleProperty(r,"border-left-color",o.e=y),f!==o.t&&e.setAttribute(a,"title",o.t=f),S!==o.a&&e.setAttribute(c,"title",o.a=S),$!==o.o&&e.setStyleProperty(l,"color",o.o=$),w!==o.i&&e.setStyleProperty(u,"color",o.i=w),C!==o.n&&e.setAttribute(u,"title",o.n=C),_!==o.s&&e.setStyleProperty(d,"color",o.s=_),I!==o.h&&e.setStyleProperty(p,"color",o.h=I),o},{e:void 0,t:void 0,a:void 0,o:void 0,i:void 0,n:void 0,s:void 0,h:void 0}),r})()}),e.createComponent(m.Show,{get when(){return s().transitions.length>0},get children(){var n=K();return n.firstChild,e.insert(n,e.createComponent(m.For,{get each(){return s().transitions},children:r=>(()=>{var a=ee(),c=a.firstChild,l=c.nextSibling,g=l.nextSibling,u=g.nextSibling,d=u.nextSibling;return e.insert(c,()=>r.time),e.insert(l,()=>r.kind),e.insert(g,()=>r.providerID),e.insert(u,()=>r.sessionID),e.insert(d,()=>`${r.active} active · ${r.queued} queued`),e.effect(p=>{var o=`request-concurrency-feed-kind is-${r.kind}`,y=r.providerID,f=r.sessionID;return o!==p.e&&e.className(l,p.e=o),y!==p.t&&e.setAttribute(g,"title",p.t=y),f!==p.a&&e.setAttribute(u,"title",p.a=f),p},{e:void 0,t:void 0,a:void 0}),a})()}),null),n}})]}})),i})()}function B(t){const s=()=>q(t.snapshot);return e.createComponent(m.Show,{get when(){return s().unavailable||s().rows.length>0},get children(){var i=ne();return i.firstChild,e.addEventListener(i,"click",()=>t.onOpen()),e.insert(i,e.createComponent(m.Show,{get when(){return!s().unavailable},get fallback(){return re()},get children(){var n=te();return e.insert(n,e.createComponent(m.For,{get each(){return s().rows},children:r=>(()=>{var a=se(),c=a.firstChild,l=c.nextSibling,g=l.nextSibling,u=g.nextSibling;return e.insert(c,()=>r.providerID),e.insert(l,()=>`${r.active}/${r.max}`),e.insert(u,()=>`${r.queued} queued`),e.effect(d=>{var p=r.utilizationColor,o=`${r.active} of ${r.max} slots in use`,y=r.demandColor,f=`${r.queued} waiting`;return p!==d.e&&e.setStyleProperty(l,"color",d.e=p),o!==d.t&&e.setAttribute(l,"title",d.t=o),y!==d.a&&e.setStyleProperty(u,"color",d.a=y),f!==d.o&&e.setAttribute(u,"title",d.o=f),d},{e:void 0,t:void 0,a:void 0,o:void 0}),a})()})),n}}),null),i}})}function ce(t){const s=v.usePlugin();return e.createComponent(s.ui.Dialog,{title:"Concurrency",size:"x-large",get children(){var i=ie();return e.insert(i,e.createComponent(x,{get snapshot(){return t.snapshot()}})),i}})}function E(){const t=v.usePlugin(),[s,i]=m.createSignal(M),[n,r]=m.createSignal(!1);m.createEffect(()=>{const c=t.servers.list().map(u=>t.servers.get(u)),l=c.find(u=>u?.builtin)??c.find(Boolean);if(!l)return;const g=T(()=>l.client.rpc(k),u=>{i(u),r(!0)});m.onCleanup(g)});const a=()=>{t.dialogs.open(()=>e.createComponent(ce,{snapshot:s}))};return e.createComponent(m.Show,{get when(){return n()},get children(){return e.createComponent(B,{get snapshot(){return s()},onOpen:a})}})}function ue(t){const[s,i]=m.createSignal(M);return m.createEffect(()=>{const n=t.session.server.client,r=t.session.directory,a=T(()=>n.rpc(k),c=>i(c),{directory:r});m.onCleanup(a)}),e.createComponent(x,{get snapshot(){return s()}})}const L={id:"status",region:"side",list:()=>[ae],render:t=>e.createComponent(ue,{get tab(){return t.tab},get session(){return t.session},get screen(){return t.screen}})},le=v.Plugin.define({setup(t){t.add(v.Panel,L),t.add(v.Slot,{at:"window.bottom",render:()=>e.createComponent(E,{})}),t.add(v.Style,N)}});exports.STATUS_UNAVAILABLE=oe;exports.StatusBar=E;exports.StatusBarBody=B;exports.StatusBody=x;exports.default=le;exports.panel=L;exports.statusBodyState=q;
