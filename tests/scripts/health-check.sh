#!/bin/bash
# health-check.sh

# Wait for the cloud-mock server to be available
echo "Waiting for cloud-mock server to be ready..."
until curl --output /dev/null --silent --head --fail http://cloud-mock:3000; do
  printf '.'
  sleep 1
done

echo "\nCloud-mock server is up and running!" 