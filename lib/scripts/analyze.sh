#!/usr/bin/env bash
set -euo pipefail

RUN_DIR="${1:?Usage: analyze.sh <run-dir>}"
RUN_DIR="${RUN_DIR%/}"

if [ ! -d "$RUN_DIR" ]; then
  echo "ERROR: directory not found: $RUN_DIR"
  exit 1
fi

PHASES_FILE="$RUN_DIR/phases.jsonl"
PROBE_FILE="$RUN_DIR/probe.jsonl"
FINGERPRINT_FILE="$RUN_DIR/cluster-fingerprint.txt"
SAFETY_FILE="$RUN_DIR/safety-plan.txt"
MODES_FILE="$RUN_DIR/modes.env"

# ---------------------------------------------------------------------------
# Helpers — parse JSON fields without jq
# ---------------------------------------------------------------------------
json_str()  { sed -n 's/.*"'"$1"'":"\([^"]*\)".*/\1/p'; }
json_num()  { sed -n 's/.*"'"$1"'":\([0-9-]*\).*/\1/p'; }

bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
dim()   { printf '\033[2m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }

divider() { echo "────────────────────────────────────────────────────────"; }

# Read a KEY=VALUE from modes.env
mode_val() { grep "^$1=" "$MODES_FILE" 2>/dev/null | head -1 | cut -d= -f2- || true; }

# Read a numeric value after a label in the fingerprint
fp_num() { grep -i "$1" "$FINGERPRINT_FILE" 2>/dev/null | head -1 | grep -o '[0-9]*' | head -1 || true; }

# ---------------------------------------------------------------------------
# 1) Run overview
# ---------------------------------------------------------------------------
section_overview() {
  bold "RUN OVERVIEW"
  divider

  echo "  Directory:  $RUN_DIR"

  if [ -f "$FINGERPRINT_FILE" ]; then
    local ctx
    ctx=$(grep '^Context:' "$FINGERPRINT_FILE" 2>/dev/null | head -1 | sed 's/^Context: *//' || echo "unknown")
    echo "  Cluster:    $ctx"

    local node_count
    node_count=$(grep -c 'node/' "$FINGERPRINT_FILE" 2>/dev/null || true)
    [ -z "$node_count" ] || [ "$node_count" = "0" ] && \
      node_count=$(grep '^Nodes:' "$FINGERPRINT_FILE" 2>/dev/null | head -1 | sed 's/^Nodes: *//' || echo "?")
    echo "  Nodes:      $node_count"

    local k8s_ver
    k8s_ver=$(grep -i 'server version' "$FINGERPRINT_FILE" 2>/dev/null | head -1 | sed 's/.*: *//' || echo "?")
    [ -n "$k8s_ver" ] && echo "  K8s:        $k8s_ver"
  fi

  if [ -f "$PHASES_FILE" ]; then
    local phase_count total_elapsed first_start last_end
    phase_count=$(wc -l < "$PHASES_FILE" | tr -d ' ')

    first_start=$(head -1 "$PHASES_FILE" | json_num start)
    last_end=$(tail -1 "$PHASES_FILE" | json_num end)
    if [ -n "$first_start" ] && [ -n "$last_end" ]; then
      total_elapsed=$((last_end - first_start))
      local mins=$((total_elapsed / 60))
      local secs=$((total_elapsed % 60))
      echo "  Phases:     $phase_count"
      echo "  Duration:   ${mins}m ${secs}s"
    fi

    local fail_count
    fail_count=$(grep -c '"rc":[1-9]' "$PHASES_FILE" 2>/dev/null || true)
    fail_count="${fail_count:-0}"
    if [ "$fail_count" = "0" ]; then
      green "  Verdict:    ALL PHASES PASSED"
    else
      red "  Verdict:    $fail_count PHASE(S) FAILED"
    fi
  else
    red "  No phases.jsonl found — incomplete run"
  fi

  echo ""
}

# ---------------------------------------------------------------------------
# 2) Phase-by-phase breakdown
# ---------------------------------------------------------------------------
section_phases() {
  [ ! -f "$PHASES_FILE" ] && return

  bold "PHASE BREAKDOWN"
  divider

  while IFS= read -r line; do
    local phase rc elapsed error
    phase=$(echo "$line" | json_str phase)
    rc=$(echo "$line" | json_num rc)
    elapsed=$(echo "$line" | json_num elapsed_s)
    error=$(echo "$line" | json_str error)

    local status_str
    if [ "$rc" = "0" ]; then
      status_str=$(green "PASS")
    else
      status_str=$(red "FAIL (rc=$rc)")
    fi

    printf '  %-22s %s  %s\n' "$phase" "${elapsed}s" "$status_str"

    if [ -n "$error" ]; then
      echo "    └─ $error"
    fi

    # Check phase log for known error patterns
    local logfile="$RUN_DIR/phase-${phase}.log"
    if [ "$rc" != "0" ] && [ -f "$logfile" ]; then
      if grep -q "timeout reached" "$logfile" 2>/dev/null; then
        yellow "    └─ kube-burner timed out waiting for objects to become ready"
        if grep -q "ImagePull" "$logfile" 2>/dev/null || grep -q "ErrImagePull" "$logfile" 2>/dev/null; then
          yellow "    └─ image pull errors detected — check image availability"
        fi
      fi
      if grep -q "not found in type" "$logfile" 2>/dev/null; then
        yellow "    └─ YAML schema error — workload template may be incompatible with this kube-burner version"
      fi
      if grep -q "unknown field" "$logfile" 2>/dev/null; then
        yellow "    └─ unknown field in workload — check template compatibility"
      fi
    fi
  done < "$PHASES_FILE"

  echo ""
}

# ---------------------------------------------------------------------------
# 3) Latency analysis
# ---------------------------------------------------------------------------
compute_latency_stats() {
  local phase="$1"
  local values count min_v max_v p50_v p95_v

  values=$(grep "\"phase\":\"${phase}\"" "$PROBE_FILE" \
    | json_num latency_ms \
    | sort -n)
  count=$(echo "$values" | grep -c . 2>/dev/null || true)
  count="${count:-0}"
  [ "$count" -eq 0 ] && return 1

  min_v=$(echo "$values" | head -1)
  max_v=$(echo "$values" | tail -1)

  local p50_idx=$(( (count * 50 + 99) / 100 ))
  local p95_idx=$(( (count * 95 + 99) / 100 ))
  [ "$p50_idx" -lt 1 ] && p50_idx=1
  [ "$p95_idx" -lt 1 ] && p95_idx=1
  [ "$p50_idx" -gt "$count" ] && p50_idx="$count"
  [ "$p95_idx" -gt "$count" ] && p95_idx="$count"
  p50_v=$(echo "$values" | sed -n "${p50_idx}p")
  p95_v=$(echo "$values" | sed -n "${p95_idx}p")

  echo "$count $min_v $p50_v $p95_v $max_v"
}

section_latency() {
  [ ! -s "$PROBE_FILE" ] && return

  bold "LATENCY ANALYSIS"
  divider

  printf '  %-22s %6s %8s %8s %8s %8s\n' "phase" "count" "min" "p50" "p95" "max"
  printf '  %-22s %6s %8s %8s %8s %8s\n' "─────" "─────" "───" "───" "───" "───"

  local baseline_p50="" baseline_p95=""
  local phases
  phases=$(grep -o '"phase":"[^"]*"' "$PROBE_FILE" | sort -u | sed 's/"phase":"//;s/"//')

  for ph in $phases; do
    local stats
    stats=$(compute_latency_stats "$ph") || continue
    local count min_v p50 p95 max_v
    read -r count min_v p50 p95 max_v <<< "$stats"

    printf '  %-22s %6s %6sms %6sms %6sms %6sms\n' "$ph" "$count" "$min_v" "$p50" "$p95" "$max_v"

    if [ "$ph" = "baseline" ]; then
      baseline_p50="$p50"
      baseline_p95="$p95"
    fi
  done

  echo ""

  # Degradation analysis (compare ramp/recovery to baseline)
  if [ -n "$baseline_p50" ] && [ "$baseline_p50" -gt 0 ]; then
    bold "DEGRADATION vs BASELINE"
    divider

    for ph in $phases; do
      [ "$ph" = "baseline" ] && continue
      local stats
      stats=$(compute_latency_stats "$ph") || continue
      local count min_v p50 p95 max_v
      read -r count min_v p50 p95 max_v <<< "$stats"

      # Calculate ratio (integer math with 1 decimal via x10)
      local ratio_x10=$(( p50 * 10 / baseline_p50 ))
      local ratio_whole=$((ratio_x10 / 10))
      local ratio_frac=$((ratio_x10 % 10))
      local ratio_str="${ratio_whole}.${ratio_frac}x"

      local delta=$((p50 - baseline_p50))

      local assessment=""
      if [ "$ratio_x10" -le 12 ]; then
        assessment=$(green "nominal  (${ratio_str} baseline)")
      elif [ "$ratio_x10" -le 20 ]; then
        assessment=$(yellow "elevated (${ratio_str} baseline, +${delta}ms)")
      elif [ "$ratio_x10" -le 50 ]; then
        assessment=$(yellow "degraded (${ratio_str} baseline, +${delta}ms)")
      else
        assessment=$(red "critical (${ratio_str} baseline, +${delta}ms)")
      fi

      printf '  %-22s p50 %5sms  %s\n' "$ph" "$p50" "$assessment"
    done

    # Recovery check
    local recovery_stats
    recovery_stats=$(compute_latency_stats "recovery" 2>/dev/null) || true
    if [ -n "$recovery_stats" ]; then
      local r_count r_min r_p50 r_p95 r_max
      read -r r_count r_min r_p50 r_p95 r_max <<< "$recovery_stats"
      local recovery_ratio_x10=$(( r_p50 * 10 / baseline_p50 ))

      echo ""
      if [ "$recovery_ratio_x10" -le 12 ]; then
        green "  Recovery: cluster returned to baseline latency levels"
      elif [ "$recovery_ratio_x10" -le 20 ]; then
        yellow "  Recovery: latency slightly elevated — cluster mostly recovered"
      else
        red "  Recovery: latency still ${recovery_ratio_x10}0% of baseline — cluster did NOT fully recover"
      fi
    fi

    echo ""
  fi
}

# ---------------------------------------------------------------------------
# 4) Stress config summary
# ---------------------------------------------------------------------------
section_config() {
  [ ! -f "$SAFETY_FILE" ] && return

  bold "STRESS CONFIGURATION"
  divider

  grep -E '^\s+(cpu|mem|disk|network|api|monitor)\s' "$SAFETY_FILE" 2>/dev/null | while IFS= read -r line; do
    echo "  $line"
  done

  local max_pods
  max_pods=$(grep 'Max cumulative pods:' "$SAFETY_FILE" 2>/dev/null | sed 's/.*: *//' || true)
  [ -n "$max_pods" ] && echo "  Max cumulative pods: $max_pods"

  echo ""
}

# ---------------------------------------------------------------------------
# 5) Failure diagnosis (resource-exhaustion vs rate-limiting aware)
# ---------------------------------------------------------------------------
section_failures() {
  [ ! -f "$PHASES_FILE" ] && return
  local fail_count
  fail_count=$(grep -c '"rc":[1-9]' "$PHASES_FILE" 2>/dev/null || true)
  fail_count="${fail_count:-0}"
  [ "$fail_count" = "0" ] && return

  # Gather capacity and throttle context for smarter diagnosis
  local ramp_qps ramp_burst kb_timeout ramp_steps
  ramp_qps=$(mode_val RAMP_QPS)
  ramp_burst=$(mode_val RAMP_BURST)
  kb_timeout=$(mode_val KB_TIMEOUT)
  ramp_steps=$(mode_val RAMP_STEPS)

  local alloc_cpu_raw alloc_pods_raw req_cpu_raw running_pods_raw
  alloc_cpu_raw=$(grep -i 'Allocatable CPU' "$FINGERPRINT_FILE" 2>/dev/null | head -1 | grep -o '[0-9]*' | head -1 || true)
  alloc_pods_raw=$(grep -i 'Allocatable Pods' "$FINGERPRINT_FILE" 2>/dev/null | head -1 | grep -o '[0-9]*' | head -1 || true)
  req_cpu_raw=$(grep -i 'Requested CPU' "$FINGERPRINT_FILE" 2>/dev/null | head -1 | grep -o '[0-9]*' | head -1 || true)
  running_pods_raw=$(grep -i 'Running Pods' "$FINGERPRINT_FILE" 2>/dev/null | head -1 | grep -o '[0-9]*' | head -1 || true)

  bold "FAILURE DIAGNOSIS"
  divider

  while IFS= read -r line; do
    local phase rc
    phase=$(echo "$line" | json_str phase)
    rc=$(echo "$line" | json_num rc)
    [ "$rc" = "0" ] && continue

    local logfile="$RUN_DIR/phase-${phase}.log"
    echo "  $phase (exit code $rc):"

    if [ ! -f "$logfile" ]; then
      echo "    No log file found"
      continue
    fi

    local diagnosed=false

    if grep -q "timeout reached" "$logfile" 2>/dev/null; then
      local timeout_val
      timeout_val=$(grep "timeout reached" "$logfile" | head -1 | grep -o '[0-9]*m[0-9]*s\|[0-9]*s' | head -1 || echo "?")
      echo "    Cause: kube-burner hit the ${timeout_val} timeout"
      diagnosed=true

      if echo "$phase" | grep -q "probe\|baseline\|recovery"; then
        echo "    Detail: the probe pod did not complete within the timeout"
        echo "    Likely: image pull failure, pod scheduling issue, or insufficient resources"
      else
        echo "    Detail: stress workload objects did not reach Ready state in time"

        # --- Smart diagnosis: is this a resource limit or a throttle? ---
        local is_throttle=false is_capacity=false

        # Check resource headroom from fingerprint
        if [ -n "$alloc_pods_raw" ] && [ -n "$running_pods_raw" ] && [ "$alloc_pods_raw" -gt 0 ] 2>/dev/null; then
          local pod_pct=$(( running_pods_raw * 100 / alloc_pods_raw ))
          if [ "$pod_pct" -ge 85 ]; then
            is_capacity=true
            echo "    Signal: pod capacity is ${pod_pct}% consumed (${running_pods_raw}/${alloc_pods_raw} allocatable pods)"
          else
            echo "    Signal: pod capacity is only ${pod_pct}% consumed — cluster has headroom"
          fi
        fi
        if [ -n "$alloc_cpu_raw" ] && [ "$alloc_cpu_raw" -gt 0 ] && [ -n "$req_cpu_raw" ] 2>/dev/null; then
          local cpu_pct=$(( req_cpu_raw * 100 / alloc_cpu_raw ))
          if [ "$cpu_pct" -ge 80 ]; then
            is_capacity=true
            echo "    Signal: CPU is ${cpu_pct}% allocated"
          fi
        fi

        # Check for kube-burner self-throttling via QPS/burst
        if [ -n "$ramp_qps" ] && [ "$ramp_qps" -le 50 ] 2>/dev/null; then
          is_throttle=true
          echo "    Signal: RAMP_QPS=$ramp_qps — kube-burner API request rate may be too low"
        fi
        if [ -n "$ramp_burst" ] && [ "$ramp_burst" -le 50 ] 2>/dev/null; then
          is_throttle=true
          echo "    Signal: RAMP_BURST=$ramp_burst — kube-burner burst limit may be too low"
        fi

        # Check if phase durations are climbing linearly (throttle signature)
        local step_num
        step_num=$(echo "$phase" | grep -o '[0-9]*$' || true)
        if [ -n "$step_num" ] && [ "$step_num" -gt 5 ]; then
          local early_dur late_dur
          early_dur=$(grep '"phase":"ramp-step-1"' "$PHASES_FILE" 2>/dev/null | json_num elapsed_s || true)
          late_dur=$(echo "$line" | json_num elapsed_s || true)
          if [ -n "$early_dur" ] && [ -n "$late_dur" ] && [ "$early_dur" -gt 0 ] 2>/dev/null; then
            local dur_ratio=$(( late_dur / early_dur ))
            if [ "$dur_ratio" -ge 3 ]; then
              is_throttle=true
              echo "    Signal: step $step_num took ${late_dur}s vs ${early_dur}s for step 1 (${dur_ratio}x increase) — consistent with API throttling"
            fi
          fi
        fi

        # Verdict
        if [ "$is_capacity" = "true" ] && [ "$is_throttle" = "false" ]; then
          red "    Assessment: RESOURCE EXHAUSTION — the cluster ran out of capacity"
        elif [ "$is_throttle" = "true" ] && [ "$is_capacity" = "false" ]; then
          yellow "    Assessment: RATE LIMITING — kube-burner is self-throttling; raise RAMP_QPS/RAMP_BURST or KB_TIMEOUT"
        elif [ "$is_throttle" = "true" ] && [ "$is_capacity" = "true" ]; then
          yellow "    Assessment: MIXED — cluster resources are high AND kube-burner may be throttling; check both"
        else
          echo "    Assessment: timeout without clear resource or throttle signal"
          echo "    Likely: insufficient cluster resources, image pull issues, or node pressure"
        fi
      fi
    fi

    if grep -q "not found in type\|unknown field" "$logfile" 2>/dev/null; then
      echo "    Cause: workload template YAML error"
      local bad_fields
      bad_fields=$(grep -o '"[^"]*" not found in type\|unknown field "[^"]*"' "$logfile" 2>/dev/null | head -3 || true)
      [ -n "$bad_fields" ] && echo "    Fields: $bad_fields"
      echo "    Fix: check kube-burner version compatibility with workload templates"
      diagnosed=true
    fi

    if grep -qi "forbidden\|unauthorized" "$logfile" 2>/dev/null; then
      echo "    Cause: RBAC permission denied"
      echo "    Fix: ensure probe-rbac.yaml is applied and kubectl context has sufficient permissions"
      diagnosed=true
    fi

    if grep -qi "no matches for kind\|the server doesn't have a resource type" "$logfile" 2>/dev/null; then
      echo "    Cause: Kubernetes API resource not available on this cluster"
      diagnosed=true
    fi

    if [ "$diagnosed" = "false" ]; then
      echo "    Cause: unknown — check the phase log for details:"
      echo "    Log: $logfile"
      local last_error
      last_error=$(grep -i 'error\|fatal\|fail' "$logfile" 2>/dev/null | tail -3 || true)
      if [ -n "$last_error" ]; then
        echo "$last_error" | while IFS= read -r eline; do
          echo "      $(echo "$eline" | sed 's/.*msg="//' | sed 's/".*//' | head -c 120)"
        done
      fi
    fi

    echo ""
  done < "$PHASES_FILE"
}

# ---------------------------------------------------------------------------
# 6) Capacity context (enriched with allocatable vs requested)
# ---------------------------------------------------------------------------
section_capacity() {
  [ ! -f "$FINGERPRINT_FILE" ] && return

  bold "CAPACITY CONTEXT"
  divider

  # Allocatable totals from fingerprint
  local alloc_cpu alloc_mem alloc_pods
  alloc_cpu=$(grep -i 'Allocatable CPU' "$FINGERPRINT_FILE" 2>/dev/null | head -1 | grep -o '[0-9]*' | head -1 || true)
  alloc_mem=$(grep -i 'Allocatable Memory' "$FINGERPRINT_FILE" 2>/dev/null | head -1 | grep -o '[0-9]*' | head -1 || true)
  alloc_pods=$(grep -i 'Allocatable Pods' "$FINGERPRINT_FILE" 2>/dev/null | head -1 | grep -o '[0-9]*' | head -1 || true)

  # Requested / running from fingerprint
  local req_cpu req_mem running_pods
  req_cpu=$(grep -i 'Requested CPU' "$FINGERPRINT_FILE" 2>/dev/null | head -1 | grep -o '[0-9]*' | head -1 || true)
  req_mem=$(grep -i 'Requested Memory' "$FINGERPRINT_FILE" 2>/dev/null | head -1 | grep -o '[0-9]*' | head -1 || true)
  running_pods=$(grep -i 'Running Pods' "$FINGERPRINT_FILE" 2>/dev/null | head -1 | grep -o '[0-9]*' | head -1 || true)

  # QPS / burst from modes.env
  local ramp_qps ramp_burst kb_timeout ramp_steps
  ramp_qps=$(mode_val RAMP_QPS)
  ramp_burst=$(mode_val RAMP_BURST)
  kb_timeout=$(mode_val KB_TIMEOUT)
  ramp_steps=$(mode_val RAMP_STEPS)

  # CPU (fingerprint values are already in millicores)
  if [ -n "$alloc_cpu" ] && [ "$alloc_cpu" -gt 0 ] 2>/dev/null; then
    if [ -n "$req_cpu" ] && [ "$req_cpu" -gt 0 ] 2>/dev/null; then
      local cpu_pct=$(( req_cpu * 100 / alloc_cpu ))
      local free_cpu=$(( alloc_cpu - req_cpu ))
      printf '  CPU:    %sm requested / %sm allocatable (%s%% used, %sm free)\n' \
        "$req_cpu" "$alloc_cpu" "$cpu_pct" "$free_cpu"
    else
      echo "  CPU:    ${alloc_cpu}m allocatable (pre-run requests not captured)"
    fi
  fi

  # Memory (fingerprint values are already in MiB)
  if [ -n "$alloc_mem" ] && [ "$alloc_mem" -gt 0 ] 2>/dev/null; then
    if [ -n "$req_mem" ] && [ "$req_mem" -gt 0 ] 2>/dev/null; then
      local mem_pct=$(( req_mem * 100 / alloc_mem ))
      local free_mem=$(( alloc_mem - req_mem ))
      printf '  Memory: %sMi requested / %sMi allocatable (%s%% used, %sMi free)\n' \
        "$req_mem" "$alloc_mem" "$mem_pct" "$free_mem"
    else
      echo "  Memory: ${alloc_mem}Mi allocatable (pre-run requests not captured)"
    fi
  fi

  # Pods
  if [ -n "$alloc_pods" ] && [ "$alloc_pods" -gt 0 ] 2>/dev/null; then
    if [ -n "$running_pods" ] 2>/dev/null; then
      local pod_pct=$(( running_pods * 100 / alloc_pods ))
      local free_pods=$(( alloc_pods - running_pods ))
      printf '  Pods:   %s running / %s allocatable (%s%% used, %s free)\n' \
        "$running_pods" "$alloc_pods" "$pod_pct" "$free_pods"
    else
      echo "  Pods:   ${alloc_pods} allocatable (pre-run count not captured)"
    fi
  fi

  echo ""

  # Rate-limit config
  if [ -n "$ramp_qps" ] || [ -n "$ramp_burst" ] || [ -n "$kb_timeout" ]; then
    bold "RATE-LIMIT & TIMEOUT CONFIG"
    divider
    [ -n "$ramp_qps" ]   && echo "  RAMP_QPS:     $ramp_qps"
    [ -n "$ramp_burst" ] && echo "  RAMP_BURST:   $ramp_burst"
    [ -n "$kb_timeout" ] && echo "  KB_TIMEOUT:   $kb_timeout"
    [ -n "$ramp_steps" ] && echo "  RAMP_STEPS:   $ramp_steps"
    echo ""
  fi
}

# ---------------------------------------------------------------------------
# 7) Actionable recommendations (resource + throttle aware)
# ---------------------------------------------------------------------------
section_recommendations() {
  [ ! -f "$PHASES_FILE" ] && return

  local recs=()

  local fail_count
  fail_count=$(grep -c '"rc":[1-9]' "$PHASES_FILE" 2>/dev/null || true)
  fail_count="${fail_count:-0}"

  # Gather context
  local ramp_qps ramp_burst kb_timeout
  ramp_qps=$(mode_val RAMP_QPS)
  ramp_burst=$(mode_val RAMP_BURST)
  kb_timeout=$(mode_val KB_TIMEOUT)

  local alloc_pods_raw running_pods_raw alloc_cpu_raw req_cpu_raw
  alloc_pods_raw=$(grep -i 'Allocatable Pods' "$FINGERPRINT_FILE" 2>/dev/null | head -1 | grep -o '[0-9]*' | head -1 || true)
  running_pods_raw=$(grep -i 'Running Pods' "$FINGERPRINT_FILE" 2>/dev/null | head -1 | grep -o '[0-9]*' | head -1 || true)
  alloc_cpu_raw=$(grep -i 'Allocatable CPU' "$FINGERPRINT_FILE" 2>/dev/null | head -1 | grep -o '[0-9]*' | head -1 || true)
  req_cpu_raw=$(grep -i 'Requested CPU' "$FINGERPRINT_FILE" 2>/dev/null | head -1 | grep -o '[0-9]*' | head -1 || true)

  if [ "$fail_count" -gt 0 ]; then
    local probe_fails ramp_fails
    probe_fails=$(grep '"rc":[1-9]' "$PHASES_FILE" 2>/dev/null | grep -c '"phase":".*probe\|baseline\|recovery"' 2>/dev/null || true)
    probe_fails="${probe_fails:-0}"
    ramp_fails=$(grep '"rc":[1-9]' "$PHASES_FILE" 2>/dev/null | grep -c '"phase":"ramp' 2>/dev/null || true)
    ramp_fails="${ramp_fails:-0}"

    if [ "$probe_fails" -gt 0 ]; then
      recs+=("Probe pods failed — verify images are available (run: kubectl get events -n kb-probe)")
      recs+=("Try increasing KB_TIMEOUT if image pulls are slow in your environment")
    fi

    if [ "$ramp_fails" -gt 0 ]; then
      # Smart recommendation based on resource vs throttle
      local has_headroom=false
      if [ -n "$alloc_pods_raw" ] && [ -n "$running_pods_raw" ] && [ "$alloc_pods_raw" -gt 0 ] 2>/dev/null; then
        local pod_pct=$(( running_pods_raw * 100 / alloc_pods_raw ))
        if [ "$pod_pct" -lt 80 ]; then
          has_headroom=true
        fi
      fi
      if [ -n "$alloc_cpu_raw" ] && [ -n "$req_cpu_raw" ] && [ "$alloc_cpu_raw" -gt 0 ] 2>/dev/null; then
        local cpu_pct=$(( req_cpu_raw * 100 / alloc_cpu_raw ))
        if [ "$cpu_pct" -lt 80 ]; then
          has_headroom=true
        fi
      fi

      local low_qps=false
      if [ -n "$ramp_qps" ] && [ "$ramp_qps" -le 50 ] 2>/dev/null; then
        low_qps=true
      fi

      if [ "$has_headroom" = "true" ] && [ "$low_qps" = "true" ]; then
        recs+=("Cluster still has resource headroom — the timeout is likely caused by kube-burner API throttling")
        recs+=("Increase RAMP_QPS (currently ${ramp_qps}) and RAMP_BURST (currently ${ramp_burst:-default}) in config.yaml")
        recs+=("Also consider raising KB_TIMEOUT (currently ${kb_timeout:-5m}) to give later steps more time")
      elif [ "$has_headroom" = "true" ]; then
        recs+=("Cluster has resource headroom — consider raising KB_TIMEOUT (currently ${kb_timeout:-5m})")
        [ -n "$ramp_qps" ] && recs+=("Current RAMP_QPS=${ramp_qps}; raise it if phase durations are climbing linearly")
      else
        recs+=("Cluster may be near capacity — reduce stress intensity or add nodes before re-running")
        recs+=("Try fewer RAMP_STEPS or lower replica counts for the next run")
      fi
    fi
  fi

  # Latency degradation
  if [ -s "$PROBE_FILE" ]; then
    local baseline_stats recovery_stats
    baseline_stats=$(compute_latency_stats "baseline" 2>/dev/null) || true
    recovery_stats=$(compute_latency_stats "recovery" 2>/dev/null) || true

    if [ -n "$baseline_stats" ] && [ -n "$recovery_stats" ]; then
      local b_p50 r_p50
      b_p50=$(echo "$baseline_stats" | awk '{print $3}')
      r_p50=$(echo "$recovery_stats" | awk '{print $3}')

      if [ "$b_p50" -gt 0 ] 2>/dev/null; then
        local ratio_x10=$(( r_p50 * 10 / b_p50 ))
        if [ "$ratio_x10" -gt 20 ]; then
          recs+=("Recovery latency is still >2x baseline — consider longer RECOVERY_PROBE_DURATION to track stabilization")
          recs+=("The cluster may need more cooldown time or the stress exposed a persistent bottleneck")
        fi
      fi
    fi
  fi

  # Only 1 ramp step
  local ramp_count
  ramp_count=$(grep -c '"phase":"ramp-step' "$PHASES_FILE" 2>/dev/null || true)
  ramp_count="${ramp_count:-0}"
  if [ "$ramp_count" -le 1 ] && [ "$fail_count" = "0" ]; then
    recs+=("Only $ramp_count ramp step ran — increase RAMP_STEPS to find the degradation threshold")
  fi

  # QPS sanity check even if no failures
  if [ -n "$ramp_qps" ] && [ "$ramp_qps" -le 20 ] 2>/dev/null && [ "$fail_count" = "0" ]; then
    recs+=("RAMP_QPS=$ramp_qps is conservative — raise it (e.g. 100-200) to make later ramp steps complete faster")
  fi

  [ ${#recs[@]} -eq 0 ] && return

  bold "RECOMMENDATIONS"
  divider
  for r in "${recs[@]}"; do
    echo "  → $r"
  done
  echo ""
}

# ===========================================================================
#  Main
# ===========================================================================
echo ""
bold "╔══════════════════════════════════════╗"
bold "║   KubePyrometer Run Analysis         ║"
bold "╚══════════════════════════════════════╝"
echo ""

section_overview
section_config
section_phases
section_latency
section_failures
section_capacity
section_recommendations
