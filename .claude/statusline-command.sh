#!/bin/bash
# Claude Code statusLine command

RESET=$'\033[0m'
RED=$'\033[31m'
YELLOW=$'\033[33m'
GREEN=$'\033[32m'
CYAN=$'\033[36m'
MAGENTA=$'\033[35m'

input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd')
arch=$(uname -m)
model=$(echo "$input" | jq -r '.model.display_name // empty')

# Git branch (replaces __git_ps1, skips optional locks)
git_branch=""
if git_branch_raw=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null); then
  if ! GIT_OPTIONAL_LOCKS=0 git -C "$cwd" diff --quiet 2>/dev/null || \
     ! GIT_OPTIONAL_LOCKS=0 git -C "$cwd" diff --cached --quiet 2>/dev/null; then
    git_branch=" [${git_branch_raw} *]"
  else
    git_branch=" [${git_branch_raw}]"
  fi
fi

# Context window bar (10 blocks, color by usage level)
# used_percentage is null until the first API response / after /compact;
# treat that as 0% so the bar is always visible.
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
pct_int=$(printf "%.0f" "$ctx_pct" 2>/dev/null)
[[ -z "$pct_int" ]] && pct_int=0
filled=$(( (pct_int * 10 + 50) / 100 ))
[[ $filled -gt 10 ]] && filled=10
[[ $filled -lt 0 ]] && filled=0
bar=""
for ((i=0; i<10; i++)); do
  [[ $i -lt $filled ]] && bar+="█" || bar+="░"
done
if [[ $pct_int -ge 80 ]]; then
  bar_color="$RED"
elif [[ $pct_int -ge 60 ]]; then
  bar_color="$YELLOW"
else
  bar_color="$GREEN"
fi
ctx_part=" ${bar_color}[${bar}]${RESET} ${pct_int}%"

# 5h rate limit: usage bar + time until reset
rate_part=""
five_hour=$(echo "$input" | jq -r '.rate_limits.five_hour // empty')
if [[ -n "$five_hour" ]]; then
  resets_at=$(echo "$five_hour" | jq -r '.resets_at // empty')
  used_pct=$(echo "$five_hour" | jq -r '.used_percentage // empty')

  # Usage bar (5 blocks, color by usage level)
  if [[ -n "$used_pct" ]]; then
    used_int=$(printf "%.0f" "$used_pct" 2>/dev/null)
    filled=$(( (used_int * 5 + 50) / 100 ))
    [[ $filled -gt 5 ]] && filled=5
    bar=""
    for ((i=0; i<5; i++)); do
      [[ $i -lt $filled ]] && bar+="█" || bar+="░"
    done
    if [[ $used_int -ge 80 ]]; then
      bar_color="$RED"
    elif [[ $used_int -ge 50 ]]; then
      bar_color="$YELLOW"
    else
      bar_color="$GREEN"
    fi
    rate_part=" ${bar_color}5h[${bar}]${used_int}%${RESET}"
  fi

  # Reset countdown
  if [[ -n "$resets_at" ]]; then
    now=$(date +%s)
    remaining=$(( resets_at - now ))
    if [[ $remaining -gt 0 ]]; then
      h=$(( remaining / 3600 ))
      m=$(( (remaining % 3600) / 60 ))
      [[ $h -gt 0 ]] && time_fmt="${h}h${m}m" || time_fmt="${m}m"
      rate_part+=" ${MAGENTA}⏱${time_fmt}${RESET}"
    fi
  fi
fi

model_part=""
[[ -n "$model" ]] && model_part=" ${CYAN}(${model})${RESET}"

echo "${YELLOW}${cwd}${RED}:($arch)${CYAN}${git_branch}${RESET}${ctx_part}${rate_part}${model_part}"
