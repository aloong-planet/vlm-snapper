// 派生文件:由 sync-mmd.mjs 从本目录 *.mmd 生成,勿手改;改图请改 .mmd 后重跑脚本。
window.MERMAID_SOURCES = window.MERMAID_SOURCES || {};
window.MERMAID_SOURCES["application-termination/quit-with-sheet"] = [
  {
    "title": "Modal sheet 与统一退出协调",
    "src": "%% title: Modal sheet 与统一退出协调\n%%{init: {\n  'theme': 'base',\n  'htmlLabels': false,\n  'state': { 'htmlLabels': false },\n  'flowchart': { 'htmlLabels': false },\n  'themeVariables': {\n    'primaryColor': '#ECECFF',\n    'primaryBorderColor': '#D5D5FF',\n    'primaryTextColor': '#000000',\n    'lineColor': '#757575',\n    'textColor': '#212121',\n    'edgeLabelBackground': 'transparent',\n    'noteBkgColor': '#FFF6B8',\n    'noteBorderColor': '#E4C800',\n    'noteTextColor': '#5C5100',\n    'tertiaryColor': '#f5f5f5',\n    'background': '#FFFFFF'\n  }\n}}%%\nstateDiagram-v2\n  direction LR\n  state \"应用运行\\nsheet 可见或无 sheet\" as Running\n  state \"统一退出协调\" as Preparing\n  state \"确认丢弃未保存结果\" as Confirming\n  state \"继续运行\\n恢复原有 sheet\" as Resumed\n  state \"正常终止\" as Terminated\n\n  [*] --> Running\n  Running --> Preparing: 菜单退出 / Command-Q / 系统 Quit\n  Preparing --> Terminated: 清理完成\n  Preparing --> Confirming: 存在未保存结果\n  Confirming --> Terminated: 确认丢弃\n  Confirming --> Resumed: 取消退出\n  Resumed --> Preparing: 再次退出\n  Terminated --> [*]\n\n  note right of Running\n    sheet 不再由 AppKit 提前取消退出\n  end note\n  note right of Resumed\n    取消退出不应关闭原有配置上下文\n  end note"
  }
];
