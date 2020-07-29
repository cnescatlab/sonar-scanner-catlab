# CNES sonar-scanner image \[client\]

![](https://github.com/lequal/sonar-scanner/workflows/CI/badge.svg?branch=develop)
![](https://github.com/lequal/sonar-scanner/workflows/CD/badge.svg?branch=develop)

> Docker environment containing open source code analysis tools configured by CNES and dedicated to Continuous Integration.

This image is a pre-configured sonar-scanner image derived from [Docker-CAT](https://github.com/lequal/docker-cat). It contains the same tools for code analysis.

SonarQube itself is an opensource project on GitHub : [SonarSource/sonarqube](https://github.com/SonarSource/sonarqube).

## Motivation of the project

LEQUAL has a need for a tool like Docker-CAT usable in Continuous Integration. In this context, it was decided to develop two Docker images usable in CI:
* A pre-configured SonarQube server with all necessary plugins, rules, quality profiles and quality gates also on GitHub : [lequal/sonarqube](https://github.com/lequal/sonarqube)
* A pre-configured sonar-scanner image that embed all necessary tools (this project)

_The use of this image in conjonction with [lequal/sonarqube](https://hub.docker.com/r/lequal/sonarqube/) is not mandatory. One may use any SonarScanner provided by SonarQube (sonar-scanner, Gradle, Maven, MSBuild...). This image only embeds other tools._

## User guide

This image is available on Docker Hub: [lequal/sonar-scanner](https://hub.docker.com/r/lequal/sonar-scanner/).

This image is based on the official SonarQube [sonar-scanner-cli docker image](https://hub.docker.com/r/sonarsource/sonar-scanner-cli) and suffer from the same limitations. Consequently, should you analyze .NET projects, use the SonarScanner for MSBuild.

1. Write a `sonar-project.properties` at the root of your project
    * For information on what to write in it, see the [official SonarQube documentation](https://docs.sonarqube.org/7.9/analysis/analysis-parameters/)
1. Execute the sonar-scanner on the project by running this image from the root of the project
    ```sh
    $ docker run \
            --rm \
            --name lequalscanner \
            -u "$(id -u):$(id -g)" \
            -e SONAR_HOST_URL="url of your SonarQube instance" \
            -v "$(pwd):/usr/src" \
            lequal/sonar-scanner
    ```
    * If the SonarQube server is running in a container on the same computer, you will need to connect both containers (server and client) to the same bridge so that they can communicate. To do so:
    ```sh
    $ docker network create -d bridge sonarbridge
    $ docker network connect sonarbridge "name of your sonarqube container"
    # add the following option to the command line when running the lequal/sonar-scanner
    --network sonarbridge
    ```

### How to use embedded tools

Not only does this image provide a sonar-scanner, but also a set of open source code analysis tools. All available tools are listed [below](#analysis-tools-included). They can be used from the image by changing the arguments of the container when running one.

```sh
# Example with shellcheck
$ docker run \
        --rm \
        -u "$(id -u):$(id -g)" \
        -v "$(pwd):/usr/src" \
        lequal/sonar-scanner \
        shellcheck --color always -s bash -f checkstyle my-script.bash
# where my-script.bash is a file in the current working directory
```

For information on how to use these tools, refer to the official documentation of the tool.

### Examples usage in CI

This image was made for CI, hence here are some examples.

_These examples still need to be tested._

#### Jenkins

Here is an example of a jenkins file that call this image to analyze a project.

```groovy
pipeline {
    agent any
    stages {
        stage('Test') {
            steps {
                sh '''
                    mkdir -p .sonarcache
                    docker run --rm \
                      -u "$(id -u):$(id -g)" \
                      -e SONAR_HOST_URL="https://my-sonarqube.com" \
                      -v "$(pwd):/usr/src" \
                      -v ".sonarcache:/opt/sonar-scanner/.sonar/cache" \
                      lequal/sonar-scanner
                '''

                cache {
                  caches {
                    path {
                      '.sonarcache'
                    }
                  }
                }
            }
        }
    }
}
```

#### GitHub Actions

Here is a GitHub Actions job of a GitHub Actions workflow that call this image to analyze a project.

```yml
jobs:
  sonar-scanning:
    name: Run CNES sonar-scanner
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Cache sonar-scanner data
        uses: actions/cache@v2
        with:
          path: .sonarcache
          key: sonar-scanner-cache
      - run: |
          mkdir -p .sonarcache
          docker run --rm \
                    -u "$(id -u):$(id -g)" \
                    -e SONAR_HOST_URL="https://my-sonarqube.com" \
                    -v "$(pwd):/usr/src" \
                    -v ".sonarcache:/opt/sonar-scanner/.sonar/cache" \
                    lequal/sonar-scanner
```

#### Travis CI

Here is a Travis CI script step, in a `.travis.yml`, to analyze a project with this image.

```yml
cache:
  directories:
    - /home/travis/.sonarcache

script:
  - mkdir -p /home/travis/.sonarcache
  - docker run --rm \
        -u "$(id -u):$(id -g)" \
        -e SONAR_HOST_URL="https://my-sonarqube.com" \
        -v "$(pwd):/usr/src" \
        -v "/home/travis/.sonarcache:/opt/sonar-scanner/.sonar/cache" \
        lequal/sonar-scanner
```

#### GitLab-CI

Here is GitLab-CI job, in a `.gitlab-ci.yml`, to analyze a project with this image.

```yml
sonar-scanning:
  stage: test
  cache:
    key: sonar-scanner-job
    paths:
      - .sonarcache
  script:
    - mkdir -p .sonarcache
    - docker run --rm \
              -u "$(id -u):$(id -g)" \
              -e SONAR_HOST_URL="https://my-sonarqube.com" \
              -v "$(pwd):/usr/src" \
              -v ".sonarcache:/opt/sonar-scanner/.sonar/cache" \
              lequal/sonar-scanner
```

## Analysis tools included

| Tool                                                  | Version              | 
|-------------------------------------------------------|----------------------|
| [ShellCheck](https://github.com/koalaman/shellcheck)  | 0.7.0                |

## Developer's guide

### How to build the image

It is a normal docker image. Thus, it can be built with the following commands.

```sh
# from the root of the project
$ docker build -t lequal/sonar-scanner .
```

To then run a container with this image see the [user guide](#user-guide).

### How to run tests

Before testing the image, it must be built (see above).

To run all the tests, use the test script.

```sh
# from the root of the project
$ ./tests/run_tests.bash
```

To run a specific test:
1. Create a docker bridge
  * ```sh
    $ docker network create sonarbridge
    ```
1. Export the environment variables the test needs
  * ```sh
    $ export SONARQUBE_CONTAINER_NAME=lequalsonarqube
    $ export SONARQUBE_ADMIN_PASSWORD=pass
    ```
1. Run a container of the SonarQube server
  * ```sh
    docker run --name "$SONARQUBE_CONTAINER_NAME" \
            -d --rm \
            --stop-timeout 1 \
            -p 9000:9000 \
            -e SONARQUBE_ADMIN_PASSWORD="$SONARQUBE_ADMIN_PASSWORD" \
            --net sonarbridge \
            lequal/sonarqube:latest
    ```
* Wait until it is configured
  * The message `[INFO] CNES LEQUAL SonarQube: ready!` is logged.
  * To see the logs of a container running in background
    ```sh
    $ docker container logs -f "$SONARQUBE_CONTAINER_NAME"
    Ctrl-C # once the container is ready
    ```
* Run a test script with 
  * ```sh
    $ ./tests/shell1.bash
    ```
* Test the exit status of the script with `echo $?`
  * zero => success
  * non-zero => failure

### How to write tests

Tests are just scripts. To add a test, create a file under the `tests/` folder and make it executable. Then, edit the script. Success and failure are given by exit statuses. A zero exist status is a success. A non-zero exit status is a failure. Note that when using `./tests/run_tests.bash`, only messages on STDERR will by displayed.

All scripted tests are listed in the [wiki](https://github.com/lequal/sonar-scanner/wiki#list-of-scripted-integration-tests).

## How to contribute

If you experienced a problem with the image please open an issue. Inside this issue please explain us how to reproduce this issue and paste the log. 

If you want to do a PR, please put inside of it the reason of this pull request. If this pull request fixes an issue please insert the number of the issue or explain inside of the PR how to reproduce this issue.

All details are available in [CONTRIBUTING](https://github.com/lequal/.github/blob/master/CONTRIBUTING.md).

Bugs and feature requests: [issues](https://github.com/lequal/sonar-scanner/issues)

## License

Licensed under the [GNU General Public License, Version 3.0](https://www.gnu.org/licenses/gpl.txt)

This project is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 3 of the License, or (at your option) any later version.
