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
#                    In this case, make sur to set necessary environment
#                    variables.
#
# Environment variables:
#   SONARQUBE_CONTAINER_NAME: the name to give to the container running
#                             the lequal/sonarqube image.
#   SONARQUBE_ADMIN_PASSWORD: the password of the admin account on the server.
#   SONARQUBE_URL: URL of lequal/sonarqube container if already running
#                  without trailing / from the scanner container.
#                  e.g. http://mycontainer:9000
#                  Use it only if no container name was given.
#   SONARQUBE_LOCAL_URL: URL of lequal/sonarqube container if already running
#                        without trailing / from the host.
#                        e.g. http://localhost:9000
#   SONARQUBE_TAG: the tag of the lequal/sonarqube image to use.
#                  e.g. latest
#   SONARQUBE_NETWORK: the name of the docker bridge used.
#
# Examples:
#   $ ./tests/run_tests.bash
#   $ SONARQUBE_CONTAINER_NAME=lequalsonarqube_sonarqube_1 SONARQUBE_ADMIN_PASSWORD=pass SONARQUBE_TAG=develop ./tests/run_tests.bash --no-run

# Include default values of environment variables and functions
. tests/functions.bash

# Unless required not to, a container is run
if [ "$1" != "--no-server-run" ]
then
    # Create the network
    docker network create "$SONARQUBE_NETWORK"

    # Run the server
    docker run --name "$SONARQUBE_CONTAINER_NAME" \
            -d --rm \
            -p 9000:9000 \
            -e SONARQUBE_ADMIN_PASSWORD="$SONARQUBE_ADMIN_PASSWORD" \
            --net "$SONARQUBE_NETWORK" \
            lequal/sonarqube:$SONARQUBE_TAG

    # When the script ends stop the server
    atexit()
    {
        docker container stop "$SONARQUBE_CONTAINER_NAME" > /dev/null
        docker network rm "$SONARQUBE_NETWORK"  > /dev/null
    }
    trap atexit EXIT
fi

# Wait the configuration of the image before running the tests
wait_cnes_sonarqube_ready "$SONARQUBE_CONTAINER_NAME"

# Prepare the cache folder
mkdir -p .sonarcache

# Launch tests
failed="0"
nb_test="0"
for script in tests/*
do
    if [ -f "$script" ] && [ -x "$script" ] && [ "$script" != "tests/run_tests.bash" ] && [ "$script" != "tests/README.md" ]
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
log "$INFO" "$failed tests failed out of $nb_test"

exit $failed
