#!/usr/bin/env bash
# shellcheck shell=bash disable=SC1072

# This script will automatically detect any new version of the GitLab Runner
# This will include all security patches of supported versions

# set nocasematch option
shopt -s nocasematch

# We have detected a new version so we are going to continue here
declare -r GIT_DEFAULT_BRANCH=main
declare -r GIT_USER_NAME=${GIT_USER_NAME:-${CI_PROJECT_NAME^^} (Bot)}
declare -r GIT_USER_EMAIL=${GIT_USER_EMAIL:-project_${CI_PROJECT_ID}_bot@${CI_SERVER_HOST}}

# Git Authentication
declare -r GIT_USERNAME=project_${CI_PROJECT_ID}_bot
declare -r GIT_ACCESS_TOKEN=${GIT_ACCESS_TOKEN:-${PROJECT_BOT_TOKEN}}
declare -r GIT_CREDENTIALS="${GIT_USERNAME}:${GIT_ACCESS_TOKEN}"

# Project DIR
declare -r CI_PROJECT_DIR=${CI_PROJECTDIR:-$(pwd)}

if [[ -z "${DEVELOP}" ]]; then
    git config user.name  "${GIT_USER_NAME}"
    git config user.email "${GIT_USER_EMAIL}"
    git config advice.detachedHead false
fi

filter_tag() {
    while read -r LINE; do
        VERSION="${LINE//.}"
        # Filter down to supported versions only
        if [[ "${VERSION}" -ge 1600 ]]; then
            echo "${LINE}"
        fi
    done
}

# Get Latest Tags
# Fetching last 200
if [[ ! -d "${CI_PROJECT_DIR}/data" ]]; then
    mkdir "${CI_PROJECT_DIR}/data"
fi
echo "Fetching Tags"
curl -s https://gitlab.com/api/v4/projects/20699/repository/tags\?per_page=200 > "${CI_PROJECT_DIR}/data/tags.json"
jq . "${CI_PROJECT_DIR}/data/tags.json" | sponge "${CI_PROJECT_DIR}/data/tags.json"

# Build Tag List
jq  -r '.[].name' < "${CI_PROJECT_DIR}/data/tags.json" > "${CI_PROJECT_DIR}/data/tags.list"

touch "${CI_PROJECT_DIR}/data/tags"
truncate -s 0 "${CI_PROJECT_DIR}/data/tags"

# Read Tags
while read -r TAG; do
    # Filter EE Edition
    if [[ ! "${TAG}" =~ \+ee ]] && [[ ! "${TAG}" =~ rc ]]; then
        VERSION="${TAG%+*}"
        VERSION_SPLIT=$(echo "${VERSION}" | tr '.' ' ')
        MAJOR=$(echo "${VERSION_SPLIT}" | awk '{print $1}')
        MINOR=$(echo "${VERSION_SPLIT}" | awk '{print $2}')
        PATCH=$(echo "${VERSION_SPLIT}" | awk '{print $3}')
        MATCH=$(((MAJOR * 100)+MINOR+PATCH))
        if [[ "${MATCH}" -ge 1600 ]]; then
            echo "${TAG} ${VERSION}" >> "${CI_PROJECT_DIR}/data/tags"
        fi
    fi
done < "${CI_PROJECT_DIR}/data/tags.list"

# Sort Version numers
sort -d -k2 --version-sort "${CI_PROJECT_DIR}/data/tags" | sponge "${CI_PROJECT_DIR}/data/tags"

# Loop remote tags
while read -r "LINE"; do
    TAG=$(echo "${LINE}" | awk '{print $1}')
    VERSION=$(echo "${LINE}" | awk '{print $2}')
    
    # Make sure we are only doing release above 16.x
    if ! git rev-parse "${TAG}" >/dev/null 2>&1; then
        # Tag does not exists, create new tag
        git commit -m "build: release ${VERSION}" --allow-empty
        git tag --delete "${VERSION}" > /dev/null 2>&1 || true
        git push --force https://${GIT_CREDENTIALS}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git :refs/tags/${VERSION} > /dev/null 2>&1 || true
        git tag --force "${VERSION}"
        git push -o ci.skip --force https://${GIT_CREDENTIALS}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git ${GIT_DEFAULT_BRANCH}
        git push https://${GIT_CREDENTIALS}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git --tags
    fi
    break
done < "${CI_PROJECT_DIR}/data/tags"

# exit 0
