FROM gcr.io/distroless/base:nonroot

ARG TARGETPLATFORM
COPY ${TARGETPLATFORM}/cosy-posts /cosy-posts

## Env vars useful for within Docker

ENV COSY_LISTEN=":80"
ENV COSY_CONTENT_DIR="/data/content"
ENV COSY_AUTH_DIR="/data/auth"

## Required env vars

ENV COSY_EMAIL_FROM=""
ENV COSY_EMAIL_RESEND_API_KEY=""

## Optional env vars

# The name of the site, as shown on the site
ENV COSY_SITE_NAME=""
# If these two are set then the command will be run when new
# content is uploaded & the site in the directory will be served
ENV COSY_SITE_BUILD_COMMAND=""
ENV COSY_SITE_DIRECTORY=""

VOLUME /data/content
VOLUME /data/auth

EXPOSE 80

ENTRYPOINT ["/cosy-posts"]
