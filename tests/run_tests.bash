#!/usr/bin/env bash

# This script is a test launcher.
# It runs a container of the lequal/sonarqube image and run analysis with
# lequal/sonar-scanner.
# It does not build any image.
#
# It must be launched from the root folder of the project like this:
#   $ ./tests/run_tests.bash
#
# Parameters:
#   --no-server-run: if this option is specified, the script will not run
#                    a lequal/sonarqube container or create a bridge network.
#                    It will only launch the tests.
#                    In this, case make sur to set environment variables
#                    like SONARQUBE_URL, SONARQUBE_ADMIN_PASSWORD or
#                    SONARQUBE_CONTAINER_NAME.
#
# Environment:
#   SONARQUBE_CONTAINER_NAME: the name to give to the container running
#                             the lequal/sonarqube image.
#   SONARQUBE_ADMIN_PASSWORD: the password of the admin account on the server.
#   SONARQUBE_URL: URL of lequal/sonarqube container if already running
#                  without trailing /. e.g. http://mycontainer:9000
#                  Use it only if no container name was given.
#   SONARQUBE_TAG: the tag of the lequal/sonarqube image to use.
#                  e.g. latest
#   SONARQUBE_NETWORK: the name of the docker bridge used.
#
# Examples:
#   $ ./tests/run_tests.bash
#   $ SONARQUBE_CONTAINER_NAME=lequalsonarqube_sonarqube_1 SONARQUBE_ADMIN_PASSWORD=pass SONARQUBE_TAG=develop ./tests/run_tests.bash --no-run

# Default values of environment variables
if [ -z "$SONARQUBE_CONTAINER_NAME" ]
then
    export SONARQUBE_CONTAINER_NAME=lequalsonarqube
fi

if [ -z "$SONARQUBE_ADMIN_PASSWORD" ]
then
    export SONARQUBE_ADMIN_PASSWORD="adminpassword"
fi

export SONARQUBE_LOCAL_URL="$SONARQUBE_URL"
if [ -z "$SONARQUBE_URL" ]
then
    export SONARQUBE_URL="http://$SONARQUBE_CONTAINER_NAME:9000"
    export SONARQUBE_LOCAL_URL="http://localhost:9000"
fi

if [ -z "$SONARQUBE_TAG" ]
then
    export SONARQUBE_TAG=latest
fi

if [ -z "$SONARQUBE_NETWORK" ]
then
    export SONARQUBE_NETWORK=sonarbridge
fi

# Unless required not to, a container is run
if [ "$1" != "--no-server-run" ]
then
    # Create the network
    docker network create "$SONARQUBE_NETWORK"

    # Run the server
    docker run --name "$SONARQUBE_CONTAINER_NAME" \
            -d --rm \
            --stop-timeout 1 \
            -p 9000:9000 \
            -e SONARQUBE_ADMIN_PASSWORD="$SONARQUBE_ADMIN_PASSWORD" \
            --net "$SONARQUBE_NETWORK" \
            lequal/sonarqube:$SONARQUBE_TAG

    # When the script ends stop the server
    atexit()
    {
        docker container stop "$SONARQUBE_CONTAINER_NAME" > /dev/null
    }
    trap atexit EXIT
fi

# Wait the configuration of the image before running the tests
while ! docker container logs "$SONARQUBE_CONTAINER_NAME" 2>&1 | grep -q '\[INFO\] CNES LEQUAL SonarQube: ready!'
do
    echo "Waiting for SonarQube to be UP."
    sleep 5
done

# Prepare the cache folder
mkdir -p .sonarcache

# Launch tests
failed="0"
nb_test="0"
for script in tests/*
do
    if [ -f "$script" ] && [ -x "$script" ] && [ "$script" != "tests/run_tests.bash" ]
    then
        # Launch each test (only print warnings and errors)
        echo -n "Launching test $script..."
        if ! ./"$script" > /dev/null;
        then
            echo "failed"
            ((failed++))
        else
            echo "success"
        fi
        ((nb_test++))
    fi
done
echo "$failed tests failed out of $nb_test"

exit $failed
