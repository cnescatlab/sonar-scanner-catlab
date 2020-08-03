#!/usr/bin/env bash

# User story:
# As a user of this image, I want to analyze a shell project
# so that I can see its level of quality on the SonarQube server.

scanner_output=$(docker run --rm -u "$(id -u):$(id -g)" \
                    -e SONAR_HOST_URL="$SONARQUBE_URL" \
                    --network "$SONARQUBE_NETWORK" \
                    -v "$(pwd):/usr/src" \
                    -v "$(pwd)/.sonarcache:/opt/sonar-scanner/.sonar/cache" \
                    lequal/sonar-scanner \
                        -Dsonar.projectBaseDir=/usr/src/tests/shell \
                        2>&1)

# Wait for SonarQube to process the results
sleep 5

# Check that the project was added to the server
projectKey="shell-dummy-project"
output=$(curl -su "admin:$SONARQUBE_ADMIN_PASSWORD" \
                "$SONARQUBE_LOCAL_URL/api/projects/search?projects=$projectKey")
key=$(echo -e "$output" | jq -r '(.components[0].key)')
if [ "$key" != "$projectKey" ]
then
    >&2 echo "Failed: the project is not on the server."
    >&2 echo "Scanner output was:"
    >&2 echo -e "$scanner_output"
    >&2 echo "curl -su" "admin:$SONARQUBE_ADMIN_PASSWORD" "$SONARQUBE_LOCAL_URL/api/projects/search?projects=$projectKey"
    >&2 echo "$output"
    exit 1
fi

# Get the number of issues of the project, there should be 58 code smells
output=$(curl -su "admin:$SONARQUBE_ADMIN_PASSWORD" \
                "$SONARQUBE_LOCAL_URL/api/issues/search?componentKeys=${projectKey}&facets=projects")
issues=$(echo "$output" | jq -r "(.facets[].values | map(select(.val == \"${projectKey}\")) | .[0].count)")
if [ "$issues" -ne 58 ]
then
    >&2 echo "Failed: there should be 58 code smells on the Shell dummy project."
    >&2 echo "curl -su" "admin:$SONARQUBE_ADMIN_PASSWORD" "$SONARQUBE_LOCAL_URL/api/issues/search?componentKeys=${projectKey}&facets=projects"
    >&2 echo "$output"
    exit 1
fi

exit 0
