#!/bin/bash

# Define spported modes
declare -a CI;
  CI=( values login check build  up  hc artifact );
declare -a CICD;
  CICD=( ${CI[*]} push push_latest );

## PROCEDURES ##
values(){
  # Check variables
  if [ -z $DOCKER_REGISTRY ] || \
     [ -z $DOCKER_USER ] || \
     [ -z $DOCKER_PSWD ] || \
     [ -z $REPO ] || \
     [ -z $BRANCH ] || \
     [ -z $COMMIT ] || \
     [ -z $BUILD ]; then
       echo "ensure that all variables sets";
       exit 2
  fi;

  #do not include 'master' at docker image
  export DOCKER_REPO=$(echo "$( echo ${REPO} )/$( echo ${BRANCH} | tr -cd '[:alnum:]' )" | tr '[:upper:]' '[:lower:]' );
  export DOCKER_REPO_ALT=$(echo "$( echo ${REPO} )" | tr '[:upper:]' '[:lower:]' );

  export TAG="${BUILD}_$(echo ${COMMIT} | cut -c 1-7)";
  export TAG_ALT="${BUILD}-$( echo ${BRANCH} | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]' )-$(echo ${COMMIT} | cut -c 1-7)";

  export IMAGE=$( echo "${DOCKER_REGISTRY}/${DOCKER_REPO}:${TAG}" )
  export IMAGE_ALT=$( echo "${DOCKER_REGISTRY}/${DOCKER_REPO_ALT}:${TAG_ALT}" )

  echo "IMAGE: $IMAGE";
  echo "IMAGE_ALT: $IMAGE_ALT";
};

login(){
  docker login ${DOCKER_REGISTRY} \
            -u ${DOCKER_USER} \
            -p ${DOCKER_PSWD} || \
            (echo "failed login: $?" && exit 11);
};

check(){
  if [ "$1" == "print" ]; then
    mode='';
  else
    mode="--services"; #print service | '--quiet' only validate config without printing anything
  fi;
  docker-compose config $mode || \
        (echo "failed config" && OK=false && exit 21);
};

build(){
  docker-compose build  || \
        (echo "failed build" && check print && exit 22);
};

up(){
  docker-compose up -d || \
        (echo "failed up" && check print && exit 23);
};

hc(){
  ScriptUrl=https://raw.githubusercontent.com/lifeci/healthchecks/1.1/compose-all.sh
  #export  DelayInput=8;
  curl -Ssk $ScriptUrl | bash -f -- || \
        (echo "failed hc" && OK=false && exit 24);
};

push(){

  echo "pushing with TAG: ${TAG}";
  docker-compose push || \
        dP="FAILED push ${TAG}, 2nd try with $TAG_ALT";

  echo "$dP";
  if [ ! -z "$dP" ]; then
    DOCKER_REPO=$DOCKER_REPO_ALT;
    TAG=$TAG_ALT;
    IMAGE=$IMAGE_ALT;
    
    docker-compose build > /dev/null;

    echo "pushing with TAG: ${TAG}";
    docker-compose push || \
          (echo "failed push ${TAG}" && exit 31 );

    artifact; #rewrite artifact with ALT naming
  fi;
};

push_latest(){
  TAG_0=$TAG; # save original tag
  export TAG=latest
  echo "pushing with TAG: ${TAG}";
  ( docker-compose build > /dev/null ) && docker-compose push || \
        (echo "failed push ${TAG}" && exit 32);
};

artifact(){
  aFolder="/tmp/${BUILD}";
  mkdir -p ${aFolder};
  if [ $MODE == "CICD" ] && [ ! -z $IMAGE ]; then
    echo "export IMAGE=$IMAGE" > ${aFolder}/VALUES || \
                  ( echo "failed export IMAGE" && exit 41 );
    echo "export TAG=$TAG" >> ${aFolder}/VALUES || \
                  ( echo "failed export TAG" && exit 42 );
  elif [ $MODE == "CI" ]; then
    echo "MODE: $MODE"             > ${aFolder}/VALUES || \
                  ( echo "failed export MODE" && exit 43 );
    echo "gitHEAD: $gitHEAD"      >> ${aFolder}/VALUES || \
                  ( echo "failed export gitHEAD" && exit 44 );
    echo "ACTIONS: ${ACTIONS[*]}" >> ${aFolder}/VALUES || \
                  ( echo "failed export ACTIONS" && exit 45 );
  else
    echo "IMAGE is empty" && exit 50;
  fi;

  cat ${aFolder}/VALUES;

};

cleanup(){
  docker-compose down;
  docker logout ${DOCKER_REGISTRY};

  printf "History entries $(history | wc -l) ";
  ( cat /dev/null > ~/.bash_history ) && printf "has beeen CLEARED\n";
  #history -c;
};


## EXECUTION LOOP ##

# choose actions
printf "\n\t### START: MODE selection ###\n";
declare -a ACTIONS;
gitHEAD=$( git status | head -1 );
if [[ "$gitHEAD" == *"pull/"*"merge"* ]]; then
  MODE="CI";
  ACTIONS=${CI[*]};
else
  MODE="CICD";
  ACTIONS=${CICD[*]};
fi;
echo "HEAD: $gitHEAD";
echo "MODE: $MODE | ACTIONS: ${ACTIONS[*]}";
printf "\t### END: MODE selection ###\n";

# runtime
for action in ${ACTIONS[@]}; do
  printf "\n\n\t### START: $action ###\n";
  $action
  exitCode=$?;
  if [ $exitCode != 0 ]; then
    printf "\t FAILED: $action with exitCode: $exitCode\n";
    break $exitCode;
  else
    printf "\t### END: $action ###\n"
  fi;
done;

printf "\n\t### START: cleanup (always) ###\n"
cleanup;  #always
printf "\t### END: cleanup (always) ###\n"

exit $exitCode
