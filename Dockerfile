FROM alpine:3.10.3

LABEL "com.github.actions.name"="PR Status Labeller"
LABEL "com.github.actions.description"="Auto-labels pull requests based on their status"
LABEL "com.github.actions.icon"="tag"
LABEL "com.github.actions.color"="gray-dark"

LABEL version="0.0.1"
LABEL repository="http://github.com/comnoco/pr-status-labeller"
LABEL homepage="http://github.com/comnoco/pr-status-labeller"
LABEL maintainer="Benjamin Nolan <benjamin.nolan@comnoco.io>"

RUN apk add --no-cache bash curl jq

ADD entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
