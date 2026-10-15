// Renderer/lifetime fixture only: no native CLI, persisted shell.json or stock desktop acceptance.
// Handles stay scene-owned: this series does not assert the restricted-projection case.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "native-runtime" as Native
import "hancore.shibumi.brightness" as Brightness
import "hancore.shibumi.state/ShibumiConfig.js" as Config
ShellRoot {
  id: scene
  property var steps: JSON.parse(Quickshell.env("STEPS"))
  property int index: 0
  property real stepDeadline: 0
  property var step: steps[index]
  property bool stock: step[0] === "omarchy"
  property var components: ({})
  property var currentBar: stock ? stockLoader.item : suiteLoader.item
  // Fixture precondition: explicitly configure the inert official audio provider;
  // the scoped resolver correctly refuses an unconfigured backend. No admission bypass.
  property var layout: ({left:["hancore.shibumi.status","hancore.shibumi.audio","hancore.shibumi.brightness"],center:["hancore.shibumi.center"],right:["omarchy.audio"]})
  property var config: ({id:stock?"omarchy.bar":"hancore.shibumi.bar",position:step[1],layout:layout})
  QtObject {
    id: state
    property bool ready: true
    property color selectedColor: "#7aa2f7"
    property int revision: 0
    property var config: {const c=Config.defaultConfig();c.presentation.shellStyle=scene.stock?"shibumi":scene.step[0];return c}
    function groupSettingsForVariant(group, variant) {return config.widgets[group] || ({})}
  }
  QtObject {id: notifications; property bool liveAvailable:true; property string historyState:"ready"; property var pendingModel:({count:2}); property var pastModel:({count:3}); property bool doNotDisturb:false}
  QtObject {id: statusService; property var notificationService:notifications; property bool stayAwake:false; property bool notificationsSilenced:false; property bool recording:false; property bool voxtypeActive:false}
  QtObject {id: audioService; property bool nativeBackendEnabled:false; property real inputPeak:0; function report() {} function release() {}}
  QtObject {id: updates; property int totalUpdateCount:4; property int packageCount:4; property int themeCount:0; property bool packageRefreshing:false; property bool themeRefreshing:false; property string packageError:""; property string themeError:""; property var packageState:({state:"ready"}); property var themeState:({checkedEpoch:1,degraded:false})}
  QtObject {
    id: host
    property var bar: scene.currentBar
    property var shellConfig: ({bar:scene.config})
    function serviceFor(id) {return ({"hancore.shibumi.state":state,"hancore.shibumi.status":statusService,"hancore.shibumi.update-center":updates,"hancore.shibumi.audio":audioService,"hancore.shibumi.brightness":monitor})[id] || null}
    function firstPartyServiceFor(id) {return null}
    function pluginShellForId(id) {return host}
    function pluginShellForBarEntry(id, name) {return host}
  }
  QtObject {
    id: registry
    property string pluginId: "hancore.shibumi.bar"
    property int revision: 0
    property var plugins: []
    property var widgets: {void(revision);const out={};for(const id of Object.keys(scene.components))out[id]={component:scene.components[id],metadata:{pluginId:id,allowMultiple:false}};return out}
    function metadataFor(id) {return widgets[id] ? widgets[id].metadata : null}
  }
  Brightness.Service {id: monitor; shell:host; barWidgetRegistry:registry}
  Loader {
    id: suiteLoader
    active: !scene.stock
    source: active ? "file:///fixture/hancore.shibumi.bar/Bar.qml" : ""
    asynchronous: true
    onLoaded: {
      item.omarchyPath=Quickshell.env("BASELINE");item.shell=host
      item.manifest=({id:"hancore.shibumi.bar",kinds:["bar"]})
      item.barWidgetRegistry=registry;item.pluginRegistry=registry
      item.barConfig=Qt.binding(function(){return scene.config})
    }
  }
  // Extend the existing window stub with an injected registry and inert widget
  // placement. This is not the native Stock.Bar layout or its admission policy.
  Loader {
    id: stockLoader
    active: scene.stock
    sourceComponent: Component {
      Native.StockBar {
        id: stockBar
        shell:host; barWidgetRegistry:registry; barConfig:scene.config
        position:scene.step[1]
        property bool vertical:false
        property color foreground:Commons.Color.foreground
        property color barForeground:foreground
        property color background:Commons.Color.background
        property color urgent:Commons.Color.accent
        property bool foregroundAnimationEnabled:false
        property var activePopout:null
        function registerClickTarget(target) {} function unregisterClickTarget(target) {}
        function showTooltip(target,text) {} function hideTooltip(target) {}
        function requestPopout(owner) {activePopout=owner} function releasePopout(owner) {if(activePopout===owner)activePopout=null}
        Repeater {
          id: placements
          model: scene.layout.left.concat(scene.layout.center)
          Loader {
            required property string modelData
            sourceComponent: scene.components[modelData] || null
            onLoaded: {item.bar=stockBar;item.moduleName=modelData}
          }
        }
        function widget(id) {for(let i=0;i<placements.count;i++){const l=placements.itemAt(i);if(l.modelData===id)return l.item}return null}
        function shutdown() {for(let i=0;i<placements.count;i++){const l=placements.itemAt(i);if(l.item)l.item.bar=null;l.active=false}}
      }
    }
  }
  function widget(id) {
    const b=currentBar
    if (!b) return null
    if(stock) return b.widget(id)
    const s=b.moduleSlots.find(s=>s.moduleName===id)
    return s ? s.activeItem : null
  }
  function descendants(item) {return item ? Array.from(item.children || []).reduce((a,c)=>a.concat([c],descendants(c)),[]) : []}
  function childState(child, bar) {
    const bound=!!child && (child.bar===bar || (child.bar && child.bar.realBar===bar))
    return {present:!!child,bound:bound,loader:child && child.parent && "status" in child.parent ? child.parent.status : -1}
  }
  function record() {
    const b=currentBar, s=widget("hancore.shibumi.status"), c=widget("hancore.shibumi.center"), a=widget("hancore.shibumi.audio"), m=widget("hancore.shibumi.brightness")
    const backend=descendants(a).find(x=>x.moduleName==="omarchy.audio")
    const row={index:index,step:step,pid:Quickshell.processId,bar:!!b,
      center:childState(c?c.updateBackend:null,b),update:childState(s?s.updateWidget:null,b),tray:childState(s?s.trayWidget:null,b),
      bell:!!s && s.bar===b && s.notificationService===notifications && s.notificationPresented,
      audio:childState(backend,b),monitor:childState(monitor.backend,b),brightness:!!m && m.bar===b}
    const ready=row.bar && row.bell && row.brightness && ["center","update","tray","audio","monitor"].every(k=>row[k].present && row[k].bound && row[k].loader===Loader.Ready)
    if(!ready && Date.now()<stepDeadline){pace.interval=100;pace.restart();return}
    console.log("BAR_SWITCH_STEP "+JSON.stringify(row))
    census.running=true
  }
  Process {
    id: census
    command:["/usr/bin/python3","/fixture/census.py"]
    stdout: StdioCollector {onStreamFinished: console.log("BAR_SWITCH_CENSUS "+this.text.trim())}
    onExited: function(code) {
      if(code!==0){Qt.exit(2);return}
      if(scene.index+1===scene.steps.length){console.log("BAR_SWITCH_DONE");Qt.exit(0);return}
      if(scene.stock && stockLoader.item)stockLoader.item.shutdown()
      scene.index++;scene.stepDeadline=Date.now()+4500;pace.interval=1200;pace.restart()
    }
  }
  Timer {id:pace; interval:1200; onTriggered:scene.record()}
  Component.onCompleted: {
    const sources={"omarchy.audio":"AudioTestPanel.qml","omarchy.monitor":"MonitorTestPanel.qml","omarchy.tray":"StatusTestWidget.qml","omarchy.system-update":"StatusTestWidget.qml"}
    for(const id of scene.layout.left.concat(scene.layout.center,["hancore.shibumi.update-center"]))sources[id]=id+"/BarWidget.qml"
    const out={};for(const id of Object.keys(sources)){const c=Qt.createComponent("file:///fixture/"+sources[id]);if(c.status!==Component.Ready){console.error(c.errorString());Qt.exit(2);return}out[id]=c}
    components=out;stepDeadline=Date.now()+4500;pace.start()
  }
}
