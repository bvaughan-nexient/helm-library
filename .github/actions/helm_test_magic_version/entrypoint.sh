#!/usr/bin/env bash
set -e

if [ -z ${TEST_PATH} ]; then
  echo "TEST_PATH is not set"
  exit 1
fi

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

get_repo_basedir() {
  git rev-parse --show-toplevel
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

lookup_local_dependency_path() {
  local chart_file="${TEST_PATH}/Chart.yaml"
  local repo_name=$(lookup_repo_name)
  local dependency_path=$(yq '.dependencies[] | select(.name == "'${repo_name}'") | .repository' ${chart_file} | sed -E 's/file:\/\/(\.\.?(\/))*//g')
  echo "$(get_repo_basedir)/${dependency_path}"
}

bump_semver_patch() {
  local version=$1
  local major=$(echo $version | cut -d. -f1)
  local minor=$(echo $version | cut -d. -f2)
  local patch=$(echo $version | cut -d. -f3)
  echo "${major}.${minor}.$((patch+1))"
}

set_target_chart_version() {
  local dependency_path=$(lookup_local_dependency_path)
  local chart_file="${dependency_path}/Chart.yaml"
  echo "chart_file: ${chart_file}"
  local current_tag=$(lookup_latest_tag)
  local prerelease_tag="$(bump_semver_patch $(chart_version_from_tag ${current_tag}))-rc.test"
  echo "prerelease_tag: ${prerelease_tag}"
  cp ${chart_file} ${chart_file}.${THIS_RANDOM_STRING}.orig
  local chart_version_value=$(yq '.version' ${chart_file})
  echo "chart_version_value: ${chart_version_value}"
  if [[ "${chart_version_value}" == "CHART_VERSION" ]]; then
    sed -i -E "s/version: .*/version: ${prerelease_tag}/" ${chart_file}
  fi
  cat ${chart_file}
}

set_target_chart_version