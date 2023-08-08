# Test documentation

The `tests/` folder contains both tests and some dummy projects to analyze.

## List of integration tests

1. Java
   - function: test_language_java
   - purpose: Check that the Java language is supported and that the right plugins are executed.
1. Shell
   - function: test_language_shell
   - purpose: Check that the Shell language is supported and that the right plugins are executed.
1. ShellCheck
   - function: test_tool_shellcheck
   - purpose: Check that ShellCheck can be launched from within the container to analyze scripts in the project.
1. Fortran
   - functions: test_language_fortran_77 and test_language_fortran_90
   - purpose: Check that the Fortran 77 and 90 languages are supported and that the right plugins are executed.
1. Python
   - function: test_language_python
   - purpose: Check that the Python language is supported and that CNES Quality Profiles are usable.
1. Pylint
   - function: test_tool_pylint
   - purpose: Check that Pylint can be launched from within the container to analyze Python projects.
1. Import pylint results in SonarQube
   - function: test_import_pylint_results
   - purpose: Check that issues revealed by a pylint analysis can be imported in SonarQube.
1. C/C++
   - function: test_language_c_cpp
   - purpose: Check that the C and C++ languages are supported and that CNES Quality Profiles are usable.
1. CppCheck
   - function: test_tool_cppcheck
   - purpose: Check that cppcheck can be launched from within the container to analyze C/C++ projects.
1. Import CppCheck results
   - function: test_import_cppcheck_results
   - purpose: Check that issues revealed by a cppcheck analysis can be imported in SonarQube.
1. Infer
   - function: test_tool_infer
   - purpose: Check that Infer can be launched from within the container to analyze C/C++ projects.

### How to run all the tests

Before testing the image, it must be built (see the [README](https://github.com/cnescatlab/sonar-scanner#how-to-build-the-image)).

To run the tests, we use [pytest](https://docs.pytest.org/en/stable/) with `Python 3.8` and the dependencies listed in _requirements.txt_. It is advised to use a virtual environment to run the tests.

```sh
# To run all the tests
$ cd tests/
$ pytest
```

```sh
# One way to set up a virtual environment (optional)
$ cd tests/
$ virtualenv -p python3.8 env
$ . env/bin/activate
$ pip install -r requirements.txt
```

## How to run a specific test

1. Activate the virtual environment (if any)
1. Create a docker bridge
   - ```sh
     $ docker network create sonarbridge
     ```
1. Run a container of the SonarQube server
   - ```sh
     $ docker run --name lequalsonarqube \
             -d --rm \
             -p 9000:9000 \
             -e SONARQUBE_ADMIN_PASSWORD=adminpassword \
             --net sonarbridge \
             lequal/sonarqube:latest
     ```

- Wait until it is configured
  - The message `[INFO] CNES SonarQube: ready!` is logged.
  - To see the logs of a container running in background
    ```sh
    $ docker container logs -f lequalsonarqube
    Ctrl-C # once the container is ready
    ```

1. Run a specific test with `pytest` and specify some environment variables
   ```sh
   $ RUN=no SONARQUBE_ADMIN_PASSWORD="adminpassword" pytest -k "<name of the test>"
   ```

## List of environment variables used by the tests

- `RUN`: whether or not to run a lequal/sonarqube container and create a bridge network, default "yes", if you already have a running container, set it to "no" and provide information through the other variables.
- `SONARQUBE_CONTAINER_NAME`: the name to give to the container running the lequal/sonarqube image.
- `SONARQUBE_ADMIN_PASSWORD`: the password of the admin account on the server.
- `SONARQUBE_URL`: URL of lequal/sonarqube container if already running without trailing / from the scanner container. e.g. http://mycontainer:9000 Use it only if no container name was given.
- `SONARQUBE_LOCAL_URL`: URL of lequal/sonarqube container if already running without trailing / from the host. e.g. http://localhost:9000
- `SONARQUBE_TAG`: the tag of the lequal/sonarqube image to use. e.g. latest
- `SONARQUBE_NETWORK`: the name of the docker bridge used.
