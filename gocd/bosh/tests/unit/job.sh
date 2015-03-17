#!/bin/bash

set -e
set -x

# Pipe all output to stderr because docker can only attach to one stream
exec 1>&2

SCRIPT_DIR=$(cd ./$(dirname $0) && pwd)
BOSH_DIR=$(cd $SCRIPT_DIR/../../../.. && pwd)
echo "BOSH_DIR: $BOSH_DIR"
cd $BOSH_DIR

if [ "$RUBY_VERSION" == "" ]; then
  echo "RUBY_VERSION environment variable is required!"
  exit 1
fi
echo "Ruby Version: $RUBY_VERSION"

source /etc/profile.d/chruby.sh

chruby $RUBY_VERSION

bundle install --local --without development

echo "Installing Go & Running unit tests..."
[[ "$COVERAGE" == "true" ]] && publish_task="ci:publish_coverage_report" || publish_task=""
bundle exec rake --trace go spec:unit $publish_task
