#!/usr/bin/env bash

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