#!/bin/bash

# Define supported modes
declare -a DRY;
  DRY=( values check build  up  hc );
declare -a CI;
  CI=( values login check build  up  hc artifact );
declare -a CICD;
  CICD=( ${CI[*]} push push_latest );

## COLORS ##
# Color output in bash https://goo.gl/DsMWYq
  ERROR='\033[0;31m'; #RED
  WARN='\033[0;33m'; # ORANGE
  OK='\033[0;32m'; # GREEN
  NC='\033[0m' # No Color
#printf "Example output text in 'printf': ${ERROR}ERROR${NC} | ${OK}All good${NC} |  ${WARN}Warning/attention${NC}\n"

## PROCEDURES ##
panic(){
  MSG=$1;
  exitCode=$2;
  execute_string=$3

  if [ -z $exitCode ]; then
    exitCode='-1';
  fi;
  printf "${ERROR}FAILED: $action $MSG${NC}\n"
  OK=false

  if [ ! -z "$execute_string" ]; then
    printf "${WARN}executing $execute_string${NC}\n";
    eval $execute_string;
  fi;

  return $exitCode;
};

values(){
  export TAG_LATEST=latest;
  # Check variables
  case $MODE in
    DRY )
        DOCKER_REGISTRY=local
        REPO=myapp
        BRANCH=master
        COMMIT=1234567890
        BUILD=9876
        echo "MODE: $MODE : setting default values";
      ;;
    CI )
        if [ -z $BRANCH ] || \
           [ -z $COMMIT ] || \
           [ -z $BUILD ]; then
             panic "ensure that all variables were set for MODE: $MODE" 2;
             #exit 2
        fi;
      ;;
    CICD )
        if [ -z $DOCKER_REGISTRY ] || \
           [ -z $DOCKER_USER ] || \
           [ -z $DOCKER_PSWD ] || \
           [ -z $REPO ] || \
           [ -z $BRANCH ] || \
           [ -z $COMMIT ] || \
           [ -z $BUILD ]; then
             panic "ensure that all variables were set for MODE: $MODE" 2;
             #exit 2
        fi;
      ;;
  esac;

  #do not include 'master' at docker image
  export DOCKER_REPO=$(echo "$( echo ${REPO} )/$( echo ${BRANCH} | tr -cd '[:alnum:]' )" | tr '[:upper:]' '[:lower:]' );
  export DOCKER_REPO_ALT=$(echo "$( echo ${REPO} )" | tr '[:upper:]' '[:lower:]' );

  export TAG="${BUILD}_$(echo ${COMMIT} | cut -c 1-7)";
  export TAG_ALT="${BUILD}-$( echo ${BRANCH} | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]' )-$(echo ${COMMIT} | cut -c 1-7)";

  export IMAGE=$( echo "${DOCKER_REGISTRY}/${DOCKER_REPO}:${TAG}" )
  export IMAGE_ALT=$( echo "${DOCKER_REGISTRY}/${DOCKER_REPO_ALT}:${TAG_ALT}" )

  echo "IMAGE: $IMAGE";
  echo "IMAGE_ALT: $IMAGE_ALT";

  export TAG_0=$TAG; # save original tag
};

login(){
  docker login ${DOCKER_REGISTRY} \
            -u ${DOCKER_USER} \
            -p ${DOCKER_PSWD} || \
            panic "exitcode: $?" 11;
            #(echo "failed login: $?" && exit 11);
};

check(){
  if [ "$1" == "print" ]; then
    mode='';
  else
    mode="--services"; #print service | '--quiet' only validate config without printing anything
  fi;
  docker-compose config $mode || \
        panic "exitcode: $?" 21;
        #(echo "failed config" && OK=false && exit 21);
};

build(){
  docker-compose build  || \
        panic "exitcode: $?" 22 "check print; docker-compose logs"
        #(echo "failed build" && check print && exit 22);
};

up(){
  docker-compose up -d || \
        panic "exitcode: $?" 23 "check print; docker-compose logs"
        #(echo "failed up" && check print && exit 23);
};

hc(){
  ScriptUrl=https://raw.githubusercontent.com/lifeci/healthchecks/1.3/compose-all.sh
  #export  DelayInput=8;
  curl -Ssk $ScriptUrl | bash -f -- || \
        panic "did not pass" 24 "check print; docker-compose logs";
};

push(){

  echo "pushing with TAG: ${TAG}";
  docker-compose push || \
        dP="FAILED push ${TAG}, 2nd try with $TAG_ALT";
  if [ ! -z "$dP" ]; then
    printf "${WARN}$dP${NC}\n";
    DOCKER_REPO=$DOCKER_REPO_ALT;
    TAG=$TAG_ALT;
    IMAGE=$IMAGE_ALT;

    docker-compose build > /dev/null;

    echo "pushing with TAG: ${TAG}";
    docker-compose push || \
          panic "TAG: ${TAG}" 31
          #(echo "failed push ${TAG}" && exit 31 );
    artifact; #rewrite artifact with ALT naming
  fi;
};

push_latest(){
  export TAG=${TAG_LATEST}
  echo "pushing with TAG: ${TAG}";
  ( docker-compose build > /dev/null ) && docker-compose push || \
        panic "TAG: ${TAG}" 32
        #(echo "failed push ${TAG}" && exit 32);
};

artifact(){
  aFolder="/tmp/${BUILD}";
  mkdir -p ${aFolder};
  if [ $MODE == "CICD" ] && [ ! -z $IMAGE ]; then
    echo "export IMAGE=$IMAGE" > ${aFolder}/VALUES || \
                  panic "export IMAGE" 41;
                  #( echo "failed export IMAGE" && exit 41 );
    echo "export TAG=$TAG" >> ${aFolder}/VALUES || \
                  panic "export TAG" 41;
                  #( echo "failed export TAG" && exit 42 );
  elif [ $MODE == "CI" ]; then
    echo "MODE: $MODE"             > ${aFolder}/VALUES || \
                  panic "export MODE" 43;
                  #( echo "failed export MODE" && exit 43 );
    echo "gitHEAD: $gitHEAD"      >> ${aFolder}/VALUES || \
                  panic "export gitHEAD" 44;
                  #( echo "failed export gitHEAD" && exit 44 );
    echo "ACTIONS: ${ACTIONS[*]}" >> ${aFolder}/VALUES || \
                  panic "export ACTIONS" 45;
                  #( echo "failed export ACTIONS" && exit 45 );
  else
    panic "VALUES is empty" 50;
  fi;
  ls -la ${aFolder};
  cat ${aFolder}/VALUES;

};

cleanup(){
  echo ":: compose ::";
  # TAG original TAG_0
  TAG=$TAG_0 docker-compose down;
  # TAG latest
  TAG=${TAG_LATEST} docker-compose down;

  echo ":: logout ::";
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

if [[ "$gitHEAD" == *"pull/"*"merge"* ]]  ; then
  MODE="CI";
  ACTIONS=${CI[*]};
elif [ "$MODE" == "DRY" ]; then
  MODE="DRY";
  ACTIONS=${DRY[*]};
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
  #if [ $exitCode != 0 ]; then
  if [ "$OK" == "false" ]; then
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
