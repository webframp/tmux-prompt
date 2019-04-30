# -*- mode: sh -*-
#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

_is_enabled() {
    ( ([ x"$1" = x"enabled" ] || [ x"$1" = x"true" ] || [ x"$1" = x"yes" ] || [ x"$1" = x"1" ]) && return 0 ) || return 1
}

_root() {
    tty=${1:-$(tmux display -p '#{pane_tty}')}
    username=$(_username "$tty" false)

    if [ x"$username" = x"root" ]; then
        tmux show -gqv '@root'
    else
        echo ""
    fi
}

_uptime() {
    case $(uname -s) in
        *Darwin*)
            boot=$(sysctl -q -n kern.boottime | awk -F'[ ,:]+' '{ print $4 }')
            now=$(date +%s)
            ;;
        *Linux*|*CYGWIN*|*MSYS*|*MINGW*)
            now=$(cut -d' ' -f1 < /proc/uptime)
            ;;
        *OpenBSD*)
            boot=$(sysctl -n kern.boottime)
            now=$(date +%s)
    esac
    # shellcheck disable=SC1004
    awk -v boot="$boot" -v now="$now" '
    BEGIN {
      uptime = now - boot
      d = int(uptime / 86400)
      h = int(uptime / 3600) % 24
      m = int(uptime / 60) % 60
      s = int(uptime) % 60

      system("tmux  set -g @uptime_d " d + 0 " \\; " \
                   "set -g @uptime_h " h + 0 " \\; " \
                   "set -g @uptime_m " m + 0 " \\; " \
                   "set -g @uptime_s " s + 0)
    }'
}

_loadavg() {
    case $(uname -s) in
        *Darwin*)
            tmux set -g @loadavg "$(sysctl -q -n vm.loadavg | cut -d' ' -f2)"
            ;;
        *Linux*)
            tmux set -g @loadavg "$(cut -d' ' -f1 < /proc/loadavg)"
            ;;
        *OpenBSD*)
            tmux set -g @loadavg "$(sysctl -q -n vm.loadavg | cut -d' ' -f1)"
            ;;
    esac
}

# see also "_apply_theme" function
_apply_overrides() {
    tmux_conf_theme_24b_colour=${tmux_conf_theme_24b_colour:-false}
    if _is_enabled "$tmux_conf_theme_24b_colour"; then
        case "$TERM" in
            screen-*|tmux-*)
            ;;
            *)
                tmux set-option -ga terminal-overrides ",$TERM:Tc"
                ;;
        esac
    fi
}

_circled_digit() {
    circled_digits='⓪ ① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨ ⑩ ⑪ ⑫ ⑬ ⑭ ⑮ ⑯ ⑰ ⑱ ⑲ ⑳'
    if [ "$1" -le 20 ] 2>/dev/null; then
        i=$(( $1 + 1 ))
        eval set -- "$circled_digits"
        eval echo "\${$i}"
    else
        echo "$1"
    fi
}

_toggle_mouse() {
    old=$(tmux show -gv mouse)
    new=""

    if [ "$old" = "on" ]; then
        new="off"
    else
        new="on"
    fi

    tmux set -g mouse $new \;\
         display "mouse: $new"
}

# _battery() {
#   charge=0
#   uname_s=$(uname -s)
#   case "$uname_s" in
#     *Darwin*)
#       while IFS= read -r line; do
#         if [ x"$discharging" != x"true" ]; then
#           discharging=$(printf '%s' "$line" | grep -qi "discharging" && echo "true" || echo "false")
#         fi
#         percentage=$(printf '%s' "$line" | grep -E -o '[0-9]+%')
#         charge=$(awk -v charge="$charge" -v percentage="${percentage%%%}" 'BEGIN { print charge + percentage / 100 }')
#         count=$((count + 1))
#       done  << EOF
# $(pmset -g batt | grep 'InternalBattery')
# EOF
#       ;;
#     *Linux*)
#       while IFS= read -r batpath; do
#         if [ x"$discharging" != x"true" ]; then
#           discharging=$(grep -qi "discharging" "$batpath/status" && echo "true" || echo "false")
#         fi
#         bat_capacity="$batpath/capacity"
#         if [ -r "$bat_capacity" ]; then
#           charge=$(awk -v charge="$charge" -v capacity="$(cat "$bat_capacity")" 'BEGIN { print charge + capacity / 100 }')
#         else
#           bat_energy_full="$batpath/energy_full"
#           bat_energy_now="$batpath/energy_now"
#           if [ -r "$bat_energy_full" ] && [ -r "$bat_energy_now" ]; then
#             charge=$(awk -v charge="$charge" -v energy_now="$(cat "$bat_energy_now")" -v energy_full="$(cat "$bat_energy_full")" 'BEGIN { print charge + energy_now / energy_full }')
#           fi
#         fi
#         count=$((count + 1))
#       done  << EOF
# $(find /sys/class/power_supply -maxdepth 1 -iname '*bat*')
# EOF
#       ;;
#     *CYGWIN*|*MSYS*|*MINGW*)
#       while IFS= read -r line; do
#         [ -z "$line" ] && continue
#         if [ x"$discharging" != x"true" ]; then
#           discharging=$(printf '%s' "$line" | awk '{ s = ($1 == 1) ? "true" : "false"; print s }')
#         fi
#         charge=$(printf '%s' "$line" | awk -v charge="$charge" '{ print charge + $2 / 100 }')
#         count=$((count + 1))
#       done  << EOF
# $(wmic path Win32_Battery get BatteryStatus, EstimatedChargeRemaining | tr -d '\r' | tail -n +2)
# EOF
#       ;;
#     *OpenBSD*)
#       for batid in 0 1 2; do
#         sysctl -n "hw.sensors.acpibat$batid.raw0" 2>&1 | grep -q 'not found' && continue
#         if [ x"$discharging" != x"true" ]; then
#           discharging=$(sysctl -n "hw.sensors.acpibat$batid.raw0" | grep -q 1 && echo "true" || echo "false")
#         fi
#         if sysctl -n "hw.sensors.acpibat$batid" | grep -q amphour; then
#           charge=$(awk -v charge="$charge" -v remaining="$(sysctl -n hw.sensors.acpibat$batid.amphour3 | cut -d' ' -f1)" -v full="$(sysctl -n hw.sensors.acpibat$batid.amphour0 | cut -d' ' -f1)" 'BEGIN { print charge + remaining / full }')
#         else
#           charge=$(awk -v charge="$charge" -v remaining="$(sysctl -n hw.sensors.acpibat$batid.watthour3 | cut -d' ' -f1)" -v full="$(sysctl -n hw.sensors.acpibat$batid.watthour0 | cut -d' ' -f1)" 'BEGIN { print charge + remaining / full }')
#         fi
#         count=$((count + 1))
#       done
#       ;;
#   esac
#   charge=$(awk -v charge="$charge" -v count="$count" 'BEGIN { print charge / count }')
#   if [ "$charge" -eq 0 ]; then
#     tmux  set -ug '@battery_status'  \;\
    #           set -ug '@battery_bar'     \;\
    #           set -ug '@battery_hbar'    \;\
    #           set -ug '@battery_vbar'    \;\
    #           set -ug '@battery_percentage'
#     return
#   fi
#
#   variables=$(tmux  show -gqv '@battery_bar_symbol_full' \;\
    #                     show -gqv '@battery_bar_symbol_empty' \;\
    #                     show -gqv '@battery_bar_length' \;\
    #                     show -gqv '@battery_bar_palette' \;\
    #                     show -gqv '@battery_hbar_palette' \;\
    #                     show -gqv '@battery_vbar_palette' \;\
    #                     show -gqv '@battery_status_charging' \;\
    #                     show -gqv '@battery_status_discharging')
#   # shellcheck disable=SC2086
#   { set -f; IFS="$__newline"; set -- $variables; unset IFS; set +f; }
#
#   battery_bar_symbol_full=$1
#   battery_bar_symbol_empty=$2
#   battery_bar_length=$3
#   battery_bar_palette=$4
#   battery_hbar_palette=$5
#   battery_vbar_palette=$6
#   battery_status_charging=$7
#   battery_status_discharging=$8
#
#   if [ x"$battery_bar_length" = x"auto" ]; then
#     columns=$(tmux -q display -p '#{client_width}' 2> /dev/null || echo 80)
#     if [ "$columns" -ge 80 ]; then
#       battery_bar_length=10
#     else
#       battery_bar_length=5
#     fi
#   fi
#
#   if [ x"$discharging" = x"true" ]; then
#     battery_status="$battery_status_discharging"
#   else
#     battery_status="$battery_status_charging"
#   fi
#
#   if echo "$battery_bar_palette" | grep -q -E '^heat|gradient(,[#a-z0-9]{7,9})?$'; then
#     # shellcheck disable=SC2086
#     { set -f; IFS=,; set -- $battery_bar_palette; unset IFS; set +f; }
#     palette_style=$1
#     battery_bg=${2:-none}
#     [ x"$palette_style" = x"gradient" ] && \
    #       palette="196 202 208 214 220 226 190 154 118 82 46"
#     [ x"$palette_style" = x"heat" ] && \
    #       palette="243 245 247 144 143 142 184 214 208 202 196"
#
#     palette=$(echo "$palette" | awk -v n="$battery_bar_length" '{ for (i = 0; i < n; ++i) printf $(1 + (i * NF / n))" " }')
#     eval set -- "$palette"
#
#     full=$(awk "BEGIN { printf \"%.0f\", ($charge) * $battery_bar_length }")
#     battery_bar="#[bg=$battery_bg]"
#     # shellcheck disable=SC2046
#     [ "$full" -gt 0 ] && \
    #       battery_bar="$battery_bar$(printf "#[fg=colour%s]$battery_bar_symbol_full" $(echo "$palette" | cut -d' ' -f1-"$full"))"
#     # shellcheck disable=SC2046
#     empty=$((battery_bar_length - full))
#     # shellcheck disable=SC2046
#     [ "$empty" -gt 0 ] && \
    #       battery_bar="$battery_bar$(printf "#[fg=colour%s]$battery_bar_symbol_empty" $(echo "$palette" | cut -d' ' -f$((full + 1))-$((full + empty))))"
#       eval battery_bar="$battery_bar#[fg=colour\${$((full == 0 ? 1 : full))}]"
#   elif echo "$battery_bar_palette" | grep -q -E '^(([#a-z0-9]{7,9}|none),?){3}$'; then
#     # shellcheck disable=SC2086
#     { set -f; IFS=,; set -- $battery_bar_palette; unset IFS; set +f; }
#     battery_full_fg=$1
#     battery_empty_fg=$2
#     battery_bg=$3
#
#     full=$(awk "BEGIN { printf \"%.0f\", ($charge) * $battery_bar_length }")
#     [ x"$battery_bg" != x"none" ] && \
    #       battery_bar="#[bg=$battery_bg]"
#     #shellcheck disable=SC2046
#     [ "$full" -gt 0 ] && \
    #       battery_bar="$battery_bar#[fg=$battery_full_fg]$(printf "%0.s$battery_bar_symbol_full" $(seq 1 "$full"))"
#     empty=$((battery_bar_length - full))
#     #shellcheck disable=SC2046
#     [ "$empty" -gt 0 ] && \
    #       battery_bar="$battery_bar#[fg=$battery_empty_fg]$(printf "%0.s$battery_bar_symbol_empty" $(seq 1 "$empty"))" && \
    #       battery_bar="$battery_bar#[fg=$battery_empty_fg]"
#   fi
#
#   if echo "$battery_hbar_palette" | grep -q -E '^heat|gradient(,[#a-z0-9]{7,9})?$'; then
#     # shellcheck disable=SC2086
#     { set -f; IFS=,; set -- $battery_hbar_palette; unset IFS; set +f; }
#     palette_style=$1
#     [ x"$palette_style" = x"gradient" ] && \
    #       palette="196 202 208 214 220 226 190 154 118 82 46"
#     [ x"$palette_style" = x"heat" ] && \
    #       palette="233 234 235 237 239 241 243 245 247 144 143 142 184 214 208 202 196"
#
#     palette=$(echo "$palette" | awk -v n="$battery_bar_length" '{ for (i = 0; i < n; ++i) printf $(1 + (i * NF / n))" " }')
#     eval set -- "$palette"
#
#     full=$(awk "BEGIN { printf \"%.0f\", ($charge) * $battery_bar_length }")
#     eval battery_hbar_fg="colour\${$((full == 0 ? 1 : full))}"
#   elif echo "$battery_hbar_palette" | grep -q -E '^([#a-z0-9]{7,9},?){3}$'; then
#     # shellcheck disable=SC2086
#     { set -f; IFS=,; set -- $battery_hbar_palette; unset IFS; set +f; }
#
#     # shellcheck disable=SC2046
#     eval $(awk "BEGIN { printf \"battery_hbar_fg=$%d\", (($charge) - 0.001) * $# + 1 }")
#   fi
#
#   eval set -- "▏ ▎ ▍ ▌ ▋ ▊ ▉ █"
#   # shellcheck disable=SC2046
#   eval $(awk "BEGIN { printf \"battery_hbar_symbol=$%d\", ($charge) * ($# - 1) + 1 }")
#   battery_hbar="#[fg=${battery_hbar_fg?}]${battery_hbar_symbol?}"
#
#   if echo "$battery_vbar_palette" | grep -q -E '^heat|gradient(,[#a-z0-9]{7,9})?$'; then
#     # shellcheck disable=SC2086
#     { set -f; IFS=,; set -- $battery_vbar_palette; unset IFS; set +f; }
#     palette_style=$1
#     [ x"$palette_style" = x"gradient" ] && \
    #       palette="196 202 208 214 220 226 190 154 118 82 46"
#     [ x"$palette_style" = x"heat" ] && \
    #       palette="233 234 235 237 239 241 243 245 247 144 143 142 184 214 208 202 196"
#
#     palette=$(echo "$palette" | awk -v n="$battery_bar_length" '{ for (i = 0; i < n; ++i) printf $(1 + (i * NF / n))" " }')
#     eval set -- "$palette"
#
#     full=$(awk "BEGIN { printf \"%.0f\", ($charge) * $battery_bar_length }")
#     eval battery_vbar_fg="colour\${$((full == 0 ? 1 : full))}"
#   elif echo "$battery_vbar_palette" | grep -q -E '^([#a-z0-9]{7,9},?){3}$'; then
#     # shellcheck disable=SC2086
#     { set -f; IFS=,; set -- $battery_vbar_palette; unset IFS; set +f; }
#
#     # shellcheck disable=SC2046
#     eval $(awk "BEGIN { printf \"battery_vbar_fg=$%d\", (($charge) - 0.001) * $# + 1 }")
#   fi
#
#   eval set -- "▁ ▂ ▃ ▄ ▅ ▆ ▇ █"
#   # shellcheck disable=SC2046
#   eval $(awk "BEGIN { printf \"battery_vbar_symbol=$%d\", ($charge) * ($# - 1) + 1 }")
#   battery_vbar="#[fg=${battery_vbar_fg?}]${battery_vbar_symbol?}"
#
#   battery_percentage="$(awk "BEGIN { printf \"%.0f%%\", ($charge) * 100 }")"
#
#   tmux  set -g '@battery_status' "$battery_status" \;\
    #         set -g '@battery_bar' "$battery_bar" \;\
    #         set -g '@battery_hbar' "$battery_hbar" \;\
    #         set -g '@battery_vbar' "$battery_vbar" \;\
    #         set -g '@battery_percentage' "$battery_percentage"
# }

# _username() {
#   tty=${1:-$(tmux display -p '#{pane_tty}')}
#   ssh_only=$2
#   # shellcheck disable=SC2039
#   if [ x"$OSTYPE" = x"cygwin" ]; then
#     pid=$(ps -a | awk -v tty="${tty##/dev/}" '$5 == tty && /ssh/ && !/vagrant ssh/ && !/autossh/ && !/-W/ { print $1 }')
#     [ -n "$pid" ] && ssh_parameters=$(tr '\0' ' ' < "/proc/$pid/cmdline" | sed 's/^ssh //')
#   else
#     ssh_parameters=$(ps -t "$tty" -o command= | awk '/ssh/ && !/vagrant ssh/ && !/autossh/ && !/-W/ { $1=""; print $0; exit }')
#   fi
#   if [ -n "$ssh_parameters" ]; then
#     # shellcheck disable=SC2086
#     username=$(ssh -G $ssh_parameters 2>/dev/null | awk 'NR > 2 { exit } ; /^user / { print $2 }')
#     # shellcheck disable=SC2086
#     [ -z "$username" ] && username=$(ssh -T -o ControlPath=none -o ProxyCommand="sh -c 'echo %%username%% %r >&2'" $ssh_parameters 2>&1 | awk '/^%username% / { print $2; exit }')
#   else
#     if ! _is_enabled "$ssh_only"; then
#       # shellcheck disable=SC2039
#       if [ x"$OSTYPE" = x"cygwin" ]; then
#         username=$(whoami)
#       else
#         username=$(ps -t "$tty" -o user= -o pid= -o ppid= -o command= | awk '
#           !/ssh/ { user[$2] = $1; ppid[$3] = 1 }
#           END {
#             for (i in user)
#               if (!(i in ppid))
#               {
#                 print user[i]
#                 exit
#               }
#           }
#         ')
#       fi
#     fi
#   fi
#
#   echo "$username"
# }

# _hostname() {
#   tty=${1:-$(tmux display -p '#{pane_tty}')}
#   ssh_only=$2
#   # shellcheck disable=SC2039
#   if [ x"$OSTYPE" = x"cygwin" ]; then
#     pid=$(ps -a | awk -v tty="${tty##/dev/}" '$5 == tty && /ssh/ && !/vagrant ssh/ && !/autossh/ && !/-W/ { print $1 }')
#     [ -n "$pid" ] && ssh_parameters=$(tr '\0' ' ' < "/proc/$pid/cmdline" | sed 's/^ssh //')
#   else
#     ssh_parameters=$(ps -t "$tty" -o command= | awk '/ssh/ && !/vagrant ssh/ && !/autossh/ && !/-W/ { $1=""; print $0; exit }')
#   fi
#   if [ -n "$ssh_parameters" ]; then
#     # shellcheck disable=SC2086
#     hostname=$(ssh -G $ssh_parameters 2>/dev/null | awk 'NR > 2 { exit } ; /^hostname / { print $2 }')
#     # shellcheck disable=SC2086
#     [ -z "$hostname" ] && hostname=$(ssh -T -o ControlPath=none -o ProxyCommand="sh -c 'echo %%hostname%% %h >&2'" $ssh_parameters 2>&1 | awk '/^%hostname% / { print $2; exit }')
#     #shellcheck disable=SC1004
#     hostname=$(echo "$hostname" | awk '\
    #     { \
    #       if ($1~/^[0-9.:]+$/) \
    #         print $1; \
    #       else \
    #         split($1, a, ".") ; print a[1] \
    #     }')
#   else
#     if ! _is_enabled "$ssh_only"; then
#       hostname=$(command hostname -s)
#     fi
#   fi
#
#   echo "$hostname"
# }

# TODO: allow better customization of colors with a "theme"
set_tmux_left_prompt() {
    tmux set -g status-left-length 1000
    tmux set -g status-left-style fg=#d4cfc9,bg=#272935
    tmux set -g status-left "#[fg=#272935,bg=#a5c261,bold] ❐ #S #[fg=#a5c261,bg=#3a4055,none]#[fg=#e6e1dc,bg=#3a4055,none] ↑#{?@uptime_d, #{@uptime_d}d,}#{?@uptime_h, #{@uptime_h}h,}#{?@uptime_m, #{@uptime_m}m,} #[fg=#3a4055,bg=default,none] "
}
set_tmux_right_prompt() {
    tmux set -g status-right-length 1000
    tmux set -g status-right-style fg=#d4cfc9,bg=#272935
    tmux set -g status-style fg=#d4cfc9,bg=#272935
    tmux set -g status-right "#(cut -c3- ~/.tmux.conf | sh -s _uptime)#(cut -c3- ~/.tmux.conf | sh -s _battery)#[fg=#272935,bg=default,none]#[fg=#d4cfc9,bg=#272935,none]#[fg=none]#[bg=none]#[none]#{?client_prefix,⌨ ,}#[fg=none]#[bg=none]#[none]#{?session_many_attached,👓 ,} #{?@battery_status, #{@battery_status},}#{?@battery_bar, #{@battery_bar},}#{?@battery_percentage, #{@battery_percentage},} #[fg=#d4cfc9,bg=#272935,none] %d %b #[fg=#da3949,bg=#272935,none]#[fg=#e6e1dc,bg=#da3949,none] #(cut -c3- ~/.tmux.conf | sh -s _username #{pane_tty} false #D)#[fg=none]#[bg=none]#[bold,blink]#(cut -c3- ~/.tmux.conf | sh -s _root #{pane_tty} #D)#[default]#[fg=#e6e1dc,bg=#da3949,none] #[fg=#e6e1dc,bg=#da3949,none]#[fg=#2b2b2b,bg=#e6e1dc,bold] #(cut -c3- ~/.tmux.conf | sh -s _hostname #{pane_tty} false #D) "
}

main() {
    tmux set -g status-position bottom
    set_tmux_left_prompt
#    set_tmux_right_prompt
}

main
