# DRAFT

## Targets
- build&run in repeatable way for developers&pipeline
- generic script for `CICD` ( Continuous Integration and Continuous Delivery ).
  Delivery means - push docker image as artifact without running at destination environment(s)
- Short syntax 'up/build/push' and env substitution via docker-compose out-of-the-box

## Requirements
### uno
from one repo build one docker image, but secondary service(s) could be defined during runtime ( if desired service will require them )

### registry
ANY existing docker registry that allow authenticate by `docker login` command

### compose
project have to be described in docker-compose.yml
Minimal docker-compose example:
```yaml
---
version: '3.6'
services:
## START BLOCK ##
  svc1:
    image: "${DOCKER_REGISTRY}/${DOCKER_REPO}:${TAG}"
    build:
      context: .
      dockerfile: Dockerfile
    networks:
      - network1
    ports:
      # it will expose port dynamically on your machine
      - ${SVC_PORT}
## END BLOCK ##

# network isolation per each build
networks:
  network1:
     name: ${TAG}
```

### health-checks
each services (even that not builded) have to have declared health-checks
```Dockerfile
...
EXPOSE ${SVC_PORT}
HEALTHCHECK  --interval=1s --timeout=2s \
  CMD wget --quiet --tries=5 --spider http://localhost:${SVC_PORT}/ready || exit $
ENTRYPOINT entrypoint.sh
```

### ENV variables:
```yaml
DOCKER_REGISTRY: $(REGISTRY)
DOCKER_USER: $(USER)
DOCKER_PSWD: $(PSWD)
REPO: $(Build.Repository.Name)
BRANCH: $(Build.SourceBranchName)
COMMIT: $(Build.SourceVersion)
BUILD: $(Build.BuildId)
DelayInput: $(DELAY_INPUT)
ScriptUrl: $(SCRIPT_URL)
```

## Usage examples

- CI&CD - default behavior
- CI - script will use mode CI if git commit came from pull request
```bash
ScriptUrl=https://raw.githubusercontent.com/lifeci/compozing/master/compozing.sh
# instead of 'master' use stable release: https://github.com/lifeci/compozing/releases
curl -Ssk $ScriptUrl | bash -f --
VALUES=$( cat /tmp/${BUILD}/VALUES )
```

## Results
- If all steps will be succeeded, script return `0`, otherwise `1` with status code and description what failed.
- For `CDP` (Continuous Deployment) need to pass docker image, so
`output of script is VALUES that have image location`
