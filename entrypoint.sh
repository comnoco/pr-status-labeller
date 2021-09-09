#!/bin/bash
set -e

if [[ -z "${GITHUB_TOKEN}" ]]; then
  echo "GITHUB_TOKEN environment variable not set."
  exit 1
fi

if [[ -z "${GITHUB_REPOSITORY}" ]]; then
  echo "GITHUB_REPOSITORY environment variable not set."
  exit 1
fi

if [[ -z "${GITHUB_EVENT_PATH}" ]]; then
  echo "GITHUB_EVENT_PATH environment variable not set."
  exit 1
fi

AWAITING_REVIEW_LABEL="${AWAITING_REVIEW_LABEL:-"awaiting review"}"
CHANGES_REQUESTED_LABEL="${CHANGES_REQUESTED_LABEL:-"changes requested"}"
CLOSED_LABEL="${CLOSED_LABEL:-"closed"}"
CODE_APPROVED_LABEL="${CODE_APPROVED_LABEL:-"code approved"}"
MERGED_LABEL="${MERGED_LABEL:-"merged"}"

REQUIRED_APPROVALS="${REQUIRED_APPROVALS:-"1"}"
if [[ "${REQUIRED_APPROVALS}" -lt "1" ]]; then
  echo "Setting REQUIRED_APPROVALS to 1, as ${REQUIRED_APPROVALS} is not a valid number of approvals to check for!"
  REQUIRED_APPROVALS="1"
fi

APPLY_MERGED_LABEL="${APPLY_MERGED_LABEL:-"true"}"
APPLY_CLOSED_LABEL="${APPLY_CLOSED_LABEL:-"true"}"

API_URI="https://api.github.com"
API_HEADER="Accept: application/vnd.github.v3+json"
AUTH_HEADER="Authorization: token ${GITHUB_TOKEN}"
COMMITS_URI="$(jq --raw-output .pull_request.base.repo.commits_url "$GITHUB_EVENT_PATH")"

action="$(jq --raw-output .action "$GITHUB_EVENT_PATH")"
state="$(jq --raw-output .review.state "$GITHUB_EVENT_PATH")"
pr_number="$(jq --raw-output .pull_request.number "$GITHUB_EVENT_PATH")"
pr_merged="$(jq --raw-output .pull_request.merged "$GITHUB_EVENT_PATH")"
commit_hash="$(jq --raw-output .pull_request.head.sha "$GITHUB_EVENT_PATH")"
labels="$(jq --raw-output '.pull_request.labels | .[] | {name: .name} | @base64' "$GITHUB_EVENT_PATH")"

add_label() {
  new_label="${1:-""}"

  exists="0"

  for l in $labels; do
    label="$(echo "${l}" | base64 -d)"
    l_name=$(echo "${label}" | jq --raw-output '.name')

    if [[ "${l_name}" == "${new_label}" ]]; then
      exists="1"
    fi
  done

  if [[ "${exists}" == "1" ]]; then
    echo "Label '${new_label}' already exists on PR"
  else
    curl -sSL \
      -H "${AUTH_HEADER}" \
      -H "${API_HEADER}" \
      -X POST \
      -H "Content-Type: application/json" \
      -d "{\"labels\":[\"${new_label}\"]}" \
      "${API_URI}/repos/${GITHUB_REPOSITORY}/issues/${pr_number}/labels"
  fi
}

remove_invalid_labels() {
  keep_label="${1:-""}"

  for l in $labels; do
    label="$(echo "${l}" | base64 -d)"
    l_name=$(echo "${label}" | jq --raw-output '.name')

    case "${l_name}" in
      "${AWAITING_REVIEW_LABEL}" | "${CHANGES_REQUESTED_LABEL}" | "${CLOSED_LABEL}" | "${CODE_APPROVED_LABEL}" | "${MERGED_LABEL}")
        if [[ "${keep_label}" != "${l_name}" ]]; then
          echo "Removing label '${l_name}'"
          curl -sSL \
            -H "${AUTH_HEADER}" \
            -H "${API_HEADER}" \
            -X DELETE \
            "${API_URI}/repos/${GITHUB_REPOSITORY}/issues/${pr_number}/labels/${l_name//" "/"%20"}"
        fi
        ;;
      esac
  done
}

update_label() {
  new_label="${1:-}"

  if [[ "${new_label}" == "" ]]; then
    echo "Removing all auto-managed labels from PR"
  else
    echo "Labelling pull request with '${new_label}'"
    add_label "${new_label}"
  fi

  remove_invalid_labels "${new_label}"
}

commit_msg=""
get_latest_commit_message() {
  # echo "COMMITS_URI: ${COMMITS_URI}"
  body=$(curl -sSL -H "${AUTH_HEADER}" -H "${API_HEADER}" "${COMMITS_URI//"{/sha}"/"/${commit_hash}"}")
  commit_msg=$(echo "${body}" | jq --raw-output '.commit.message')
}

label_as_approved_or_awaiting_review() {
  echo "Waiting 5 seconds for the GitHub API to update the reviews endpoint..."
  sleep 5
  # https://developer.github.com/v3/pulls/reviews/#list-reviews-on-a-pull-request
  body=$(curl -sSL -H "${AUTH_HEADER}" -H "${API_HEADER}" "${API_URI}/repos/${GITHUB_REPOSITORY}/pulls/${pr_number}/reviews?per_page=100")
  # echo "${body}"
  reviews=$(echo "${body}" | jq --raw-output '.[] | {state: .state} | @base64')

  approvals=0

  for r in $reviews; do
    review="$(echo "${r}" | base64 -d)"
    r_state=$(echo "${review}" | jq --raw-output '.state')

    if [[ "${r_state}" == "APPROVED" ]]; then
      approvals=$((approvals+1))
      # else
      # echo "Got review with state '${r_state}'"
    fi

    if [[ "${approvals}" -ge "${REQUIRED_APPROVALS}" ]]; then
      update_label "${CODE_APPROVED_LABEL}"

      break
    fi
  done

  echo "Found ${approvals} / ${REQUIRED_APPROVALS} approvals"

  if [[ "${approvals}" -lt "${REQUIRED_APPROVALS}" ]]; then
    update_label "${AWAITING_REVIEW_LABEL}"
  fi
}

if [[ "${GITHUB_EVENT_NAME}" == "pull_request" ]]; then
  if [[ "${action}" == "closed" ]]; then
    if [[ "${pr_merged}" == "false" ]] && [[ "${APPLY_CLOSED_LABEL}" == "true" ]]; then
      update_label "${CLOSED_LABEL}"
    elif [[ "${pr_merged}" == "true" ]] && [[ "${APPLY_MERGED_LABEL}" == "true" ]]; then
      update_label "${MERGED_LABEL}"
    else
      echo "Ignoring event ${GITHUB_EVENT_NAME}/${action}/${state}"
    fi
  elif [[ "${action}" == "opened" ]] || [[ "${action}" == "reopened" ]] || [[ "${action}" == "review_requested" ]] || [[ "${action}" == "review_request_removed" ]] || [[ "${action}" == "ready_for_review" ]]; then
    label_as_approved_or_awaiting_review
  elif [[ "${action}" == "synchronize" ]]; then
    # cat "${GITHUB_EVENT_PATH}"
    get_latest_commit_message
    echo "Commit message: ${commit_msg}"
    if [[ "${commit_msg}" == "Merge branch '"* ]]; then
      echo "Ignoring merge commit on event ${GITHUB_EVENT_NAME}/${action}/${state}"
    else
      label_as_approved_or_awaiting_review
    fi
  else
    echo "Ignoring event ${GITHUB_EVENT_NAME}/${action}/${state}"
  fi
elif [[ "${GITHUB_EVENT_NAME}" == "pull_request_review" ]]; then
  if [[ "${action}" == "submitted" ]] || [[ "${action}" == "edited" ]]; then
    if [[ "${state}" == "approved" ]]; then
      label_as_approved_or_awaiting_review
    else
      echo "Ignoring event ${GITHUB_EVENT_NAME}/${action}/${state}"
    fi
  elif [[ "${action}" == "changes_requested" ]]; then
    update_label "${CHANGES_REQUESTED_LABEL}"
  elif [[ "${action}" == "dismissed" ]]; then
    label_as_approved_or_awaiting_review
  else
    echo "Ignoring event ${GITHUB_EVENT_NAME}/${action}/${state}"
  fi
else
  echo "Ignoring event ${GITHUB_EVENT_NAME}/${action}/${state}"
fi
