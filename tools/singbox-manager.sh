#!/usr/bin/env bash
# Management entry point for the systemd deployment.
set -euo pipefail
WORKDIR=/root/sing-box
UNIT=sing-box.service

usage() {
    cat <<'HELP'
singbox 管理命令
  start / stop / restart   启动 / 停止 / 重启
  status                  查看服务状态
  check                   检查配置
  link                    显示节点链接（包含密码，请勿公开）
  logs / logx             最近日志 / 持续查看日志
  version                 查看内核版本
  auto enable|disable|status  管理开机启动
HELP
}

action=${1:-}
if [[ -z "$action" ]]; then
    usage
    if [[ ! -t 0 ]]; then exit 0; fi
    printf '\n1) 状态  2) 启动  3) 停止  4) 重启  5) 节点  6) 配置检查  0) 退出\n'
    read -r -p '请选择: ' choice || exit 0
    case "$choice" in
        1) action=status ;; 2) action=start ;; 3) action=stop ;;
        4) action=restart ;; 5) action=link ;; 6) action=check ;;
        0|'') exit 0 ;; *) echo '无效选项' >&2; exit 2 ;;
    esac
fi

case "$action" in
    start|stop|restart)
        systemctl "$action" "$UNIT"
        echo "已执行: $action"
        ;;
    status) systemctl status "$UNIT" --no-pager ;;
    check)
        cd "$WORKDIR"
        ./sing-box check -c config.json
        echo '配置检查通过'
        ;;
    link|links) cat "$WORKDIR/web/list.txt" ;;
    logs|logx)
        if [[ -f "$WORKDIR/sing-box.log" ]]; then
            if [[ "$action" == logx ]]; then exec tail -n 50 -F "$WORKDIR/sing-box.log"; fi
            tail -n 50 "$WORKDIR/sing-box.log"
        else
            if [[ "$action" == logx ]]; then exec journalctl -u "$UNIT" -n 50 -f; fi
            journalctl -u "$UNIT" -n 50 --no-pager
        fi
        ;;
    version) "$WORKDIR/sing-box" version ;;
    auto)
        case "${2:-status}" in
            enable|disable) systemctl "$2" "$UNIT" ;;
            status) systemctl is-enabled "$UNIT" ;;
            *) usage >&2; exit 2 ;;
        esac
        ;;
    help|-h|--help) usage ;;
    *) usage >&2; exit 2 ;;
esac
