#!/usr/bin/env bash
set -e

if [ -z ${VERSION} ]; then
  echo "VERSION is not set"
  exit 1
fi

if [ -z ${CHART_PATH} ]; then
  echo "CHART_PATH is not set"
  exit 1
else
  if [ ! -f ${CHART_PATH} ]; then
    CHART_PATH=${CHART_PATH}/Chart.yaml
  fi
fi

set_target_chart_version() {
  local chart_file="${CHART_PATH}"
  sed -i -E "s/version: .*/version: ${VERSION}/" ${chart_file}
  cat ${chart_file}
}

set_target_chart_version