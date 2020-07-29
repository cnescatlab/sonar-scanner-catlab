#!/usr/bin/env bash

# User story:
# As a user of this image, I want to analyze a shell project
# so that I can see its level of quality on the SonarQube server.

docker run --rm -u "$(id -u):$(id -g)" \
           -e SONAR_HOST_URL="$SONARQUBE_URL" \
           --network "$SONARQUBE_NETWORK" \
           -v "$(pwd):/usr/src" \
           -v "$(pwd)/.sonarcache:/opt/sonar-scanner/.sonar/cache" \
           lequal/sonar-scanner \
              -Dsonar.projectBaseDir=/usr/src/tests/shell \
            2>&1

# Wait for SonarQube to process the results
sleep 5

# Check that the project was added to the server
projectKey="shell-dummy-project"
key=$(curl -su "admin:$SONARQUBE_ADMIN_PASSWORD" "$SONARQUBE_LOCAL_URL/api/projects/search?projects=$projectKey" | jq -r '(.components[0].key)')
if [ "$key" != "$projectKey" ]
then
    >&2 echo "Failed: the project is not on the server."
    exit 1
fi

# Get the number of issues of the project, there should be 58 code smells
issues=$(curl -su "admin:$SONARQUBE_ADMIN_PASSWORD" "$SONARQUBE_LOCAL_URL/api/issues/search?componentKeys=${projectKey}&facets=projects" | jq -r "(.facets[].values | map(select(.val == \"${projectKey}\")) | .[0].count)")
if [ "$issues" -ne 58 ]
then
    >&2 echo "Failed: there should be 58 code smells on the Shell dummy project."
    exit 1
fi

exit 0
