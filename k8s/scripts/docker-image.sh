#!/bin/bash

# Any subsequent commands which fail will cause the
# shell script to exit immediately
set -e

# print usage
usage() {
  echo -n "docker-image.sh [OPTION]... [MODULE]

build/tag/push miro docker images
if no MODULE is specified all modules are processed

 Options:
  -a           Parallel build with background jobs
  -b           Build the image
  -c           Build With Cache
  -g           Tag the image with the output of 'git describe'
  -h           Display this help and exit
  -p           Push the image
  -r [STRING]  Docker registry (eg. 1.1.1.1:5000)
  -s [STRING]  Source tag, used during the tag operation to specify which image
               should be tagged
  -t [STRING]  Tag to apply to the image (the build operation tags with 'latest')
"

exit 0
}

# build_image: builds docker image
# $1 : docker registry (eg. 1.1.1.1:5000)
# $2 : image name (eg. evox-modules-api-db)
# $3 : image tag (eg. latest)
# $4 : Dockerfile path
# $5 : docker CWD
# $6 : dockerignore file path
#
build_image() {
  # dockerignore is not suitable for parallel buids
  if ! $PARALLEL; then
    echo -e "cp $6 $5/.dockerignore"
    cp $6 $5/.dockerignore
  fi

  if $CACHE; then
    echo -e "docker build --pull -t $1"/"$2":"$3 -f $4 $5"
    docker build -t $1"/"$2":"$3 -f $4 $5
  else
    echo -e "docker build --pull --no-cache -t $1"/"$2":"$3 -f $4 $5"
    docker build --no-cache -t $1"/"$2":"$3 -f $4 $5
  fi
}

# tag_image: add tag to a docker image
# $1 : docker registry (eg. 1.1.1.1:5000)
# $2 : image name (eg. miro-modules-api)
# $3 : source tag (used to specify which image to tag)
# $4 : tag to apply
#
tag_image() {
  echo -e "docker tag $1"/"$2":"$3 $1"/"$2":"$4"
  docker tag $1"/"$2":"$3 $1"/"$2":"$4
}

# push_image: push image to the registry
# $1 : docker registry (eg. 1.1.1.1:5000)
# $2 : image name (eg. miro-modules-api)
#
push_image() {
  echo -e "docker push $1"/"$2"
  docker push $1"/"$2

  if [ "$TAG" != "latest" ]; then
    echo -e "docker push $1"/"$2:$TAG"
    docker push $1"/"$2:"$TAG"
  fi
}

escape() {
  sed 's/[^^]/[&]/g; s/\^/\\^/g' <<<"$1";
}

PREFIX="miro"
REGISTRY="localhost:5000"
TAG="latest"
SOURCE_TAG="latest"
BUILD=false
PUSH=false
VERSION=""
PARALLEL=false
CACHE=false
DOCKER_LOG_TMP_DIR="/tmp/docker_build_logs/"
mkdir -p "$DOCKER_LOG_TMP_DIR"

while getopts "r:e:t:s:abcgph" flag; do
case "$flag" in
    a) PARALLEL=true;;
    b) BUILD=true;;
    c) CACHE=true;;
    g) VERSION=$(git describe | xargs echo -n);;
    h) usage;;
    p) PUSH=true;;
    r) REGISTRY=$OPTARG;;
    s) SOURCE_TAG=$OPTARG;;
    t) TAG=$OPTARG;;
esac
done

MODULE_OPT=${@:$OPTIND:1}
#ARG2=${@:$OPTIND+1:1}

REGISTRY=$REGISTRY
echo -e "Using docker registry: "$REGISTRY

if [ "$TAG" != "latest" ]; then
  echo -e "Using tag: "$TAG
fi

if [ "$VERSION" != "" ]; then
  echo -e "Project version: "$VERSION
fi

if [ "$MODULE_OPT" == "" ]; then
  DOCKERFILES=$(find ./modules -maxdepth 4 -name "Dockerfile" | sort)
else
  DOCKERFILES="./"$MODULE_OPT"/Dockerfile"
fi


# do_work: work to be paralelizzed with wait
do_work() {
  if $BUILD; then
    echo -e "===Building image==="
    build_image $REGISTRY $IMAGE_NAME "latest" $DOCKERFILE "./modules" $DOCKERIGNORE
  fi

  if [ "$TAG" != "latest" ]; then
    echo -e "\n===Applying tag ("$TAG") to image==="
    tag_image $REGISTRY $IMAGE_NAME $SOURCE_TAG $TAG
  fi

  if [ "$VERSION" != "" ]; then
    echo -e "\n===Applying version ("$VERSION") tag to image==="
    tag_image $REGISTRY $IMAGE_NAME $SOURCE_TAG $VERSION
  fi

  if $PUSH; then
    echo -e "\n===Pushing image==="
    push_image $REGISTRY $IMAGE_NAME
  fi
}

# create a tmp dir for storing the global dockerignore
# and to generate the current dockerignore
DOCKER_TMP_DIR="$(pwd)/docker_tmp"
mkdir -p "$DOCKER_TMP_DIR"

# cycle all the dockerfiles and generate a master dockerignore
# with all modules in it to be excaped in the next cycle
ALL_DOCKERFILES=$(find ./modules -maxdepth 4 -name "Dockerfile" | sort)
> "$DOCKER_TMP_DIR"/dockerignore
for i in $ALL_DOCKERFILES
do
  MODULE=$(echo ${i%/*} | cut -c3- | sed 's/^modules\///')
  echo $MODULE >> "$DOCKER_TMP_DIR"/dockerignore
done

# cycle all the dockerfiles and send to background the
# building of images to be recovered by the pids
# Every build uses a tmp file to store output to be sequentialy
# sent to stdout with cat in the next cycle
for i in $DOCKERFILES
do
  # MODULE=$(echo ${i::-11} | cut -c3-)
  MODULE=$(echo ${i%/*} | cut -c3-)
  CURRENT_DOCKERIGNORE_MODULE=$(echo ${i%/*} | cut -c3- | sed 's/^modules\///')
  DOCKERFILE=$i
  sed "/$(escape "$CURRENT_DOCKERIGNORE_MODULE")/d" "$DOCKER_TMP_DIR/dockerignore" > "$DOCKER_TMP_DIR/tmp.dockerignore"
  DOCKERIGNORE="$DOCKER_TMP_DIR/tmp.dockerignore"
  #IMAGE_NAME=$PREFIX"-"$(echo $MODULE | tr "/" "-")
  IMAGE_NAME=$(echo $MODULE | tr "/" "-")
  echo -e "\n\nProcessing module: "$MODULE
  if $PARALLEL; then
    do_work > "$DOCKER_LOG_TMP_DIR$!.log" &
    pids="$pids $!"
  else
    do_work
  fi
done

if $PARALLEL; then
  # get the pids to handle exitcodes and print cached logs
  for i in ${pids[@]}
  do
    wait $i
    exitcode=$?
    cat "$DOCKER_LOG_TMP_DIR$i.log" && rm -r "$DOCKER_LOG_TMP_DIR$i.log"
    if [ "$exitcode" -eq "1" ]; then
      exit 1
    fi
  done
fi

function prune {

  echo -e "\n===Remove all stopped containers==="
  docker container prune -f

  echo -e "\n===Remove unused images==="
  docker image prune -f

  echo -e "\n===Remove all unused networks==="
  docker network prune -f

  echo -e "\n===Remove all unused volumes==="
  docker volume prune -f

}

prune

# remove the temp dir used for dockerignore and log files
rm -rf "$DOCKER_TMP_DIR"
rm -rf "$DOCKER_LOG_TMP_DIR"
rm -f ./modules/.dockerignore
