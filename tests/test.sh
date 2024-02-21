#!/usr/bin/env bash

set -e

# This is a simple test script to test the functionality of the helm chart
if [ -f /opt/homebrew/bin/gfind -a -x /opt/homebrew/bin/gfind ]; then
  FIND=/opt/homebrew/bin/gfind
else
  FIND=$(which find)
fi
valfiles=$(${FIND} . -type f -regextype egrep -iregex "./values.*ya?ml")
KUBEVERSION="1.26.5"
mkdir -p outputs
TMPDIR=$(mktemp -d --tmpdir=./outputs/)
TAG_SEPARATOR="-"

random_string() {
  local length=${1:-8}
  # Yes, I know this is not a good random number generator. It's good enough for our purposes.
  echo $(echo $(date +%s%N) | sha256sum | base64 | head -c ${length} ; echo)
}
THIS_RANDOM_STRING=$(random_string)

lookup_repo_name() {
  basename `git rev-parse --show-toplevel`
}

lookup_latest_tag() {
  git fetch --tags >/dev/null 2>&1

  if ! git describe --tags --abbrev=0 HEAD~ 2>/dev/null; then
    git rev-list --max-parents=0 --first-parent HEAD
  fi
}

chart_version_from_tag() {
  local tag=$1
  local repo_name=$(lookup_repo_name)
  echo ${tag} | sed "s/^${repo_name}${TAG_SEPARATOR}//"
}

lookup_dependency_path() {
  local chart_file="./Chart.yaml"
  local repo_name=$(lookup_repo_name)
  local dependency_path=$(yq '.dependencies[] | select(.name == "'${repo_name}'") | .repository' ${chart_file} | sed 's/file:\/\/\(.*\)/\1/')
  echo "${dependency_path}"
}

restore_target_chart_file() {
  local dependency_path=$(lookup_dependency_path)
  local chart_file="${dependency_path}/Chart.yaml"
  local orig_chart_file="${chart_file}.${THIS_RANDOM_STRING}.orig"
  if [ -f ${orig_chart_file} ]; then
    echo "putting back the original chart file"
    mv ${orig_chart_file} ${chart_file}
  else 
    echo "original chart file not found"
  fi
}

bump_semver_patch() {
  local version=$1
  local major=$(echo $version | cut -d. -f1)
  local minor=$(echo $version | cut -d. -f2)
  local patch=$(echo $version | cut -d. -f3)
  echo "${major}.${minor}.$((patch+1))"
}

set_target_chart_version() {
  local dependency_path=$(lookup_dependency_path)
  local chart_file="${dependency_path}/Chart.yaml"
  local current_tag=$(lookup_latest_tag)
  local prerelease_tag="$(bump_semver_patch $(chart_version_from_tag ${current_tag}))-prerelease"
  cp ${chart_file} ${chart_file}.${THIS_RANDOM_STRING}.orig
  local chart_version_value=$(yq '.version' ${chart_file})
  if [[ "${chart_version_value}" == "CHART_VERSION" ]]; then
    sed -i '' "s/version: .*/version: ${prerelease_tag}/" ${chart_file}
  fi
  cat ${chart_file}
}

cleanup() {
  if [ -d  "./charts" ]; then
    rm -rf ./charts
  fi
  if [ -f "Chart.lock" ]; then
    rm -f Chart.lock
  fi
  if [ -d ${TMPDIR} ]; then
    rm -rf ${TMPDIR}
  fi
  restore_target_chart_file
}

trap cleanup EXIT

set_target_chart_version

for file in $valfiles; do
  echo "Testing $file"
  
  OUTDIR=${TMPDIR}/${file}
  mkdir -p $OUTDIR
  OUTFILE=${OUTDIR}/test-manifest.yaml
  if [ -f Chart.lock ]; then
    rm -f Chart.lock
  fi

  helm dependencies update
  helm template . --values=${file} --debug --output-dir $OUTDIR
  if [ $? -eq 0 ]; then
    echo "Helm chart is able to generate the manifest files successfully"
  else
    echo "Helm chart build failed"
    exit 1
  fi

  helm lint . --debug --values=${file}
  if [ $? -eq 0 ]; then
    echo "Helm chart is linting successfully"
  else
    echo "Helm chart linting failed"
    exit 1
  fi

  kubeconform -strict -summary -kubernetes-version $KUBEVERSION -exit-on-error $OUTDIR
  if [ $? -eq 0 ]; then
    echo "Manifest file is valid"
    for file in $(find ${OUTDIR} -type f -name "*.yaml"); do
      echo $file; echo; echo; cat $file; echo; echo;
    done
  else
    echo "Manifest file is invalid"
    exit 1
  fi
done
