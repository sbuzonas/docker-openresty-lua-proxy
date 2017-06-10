FROM sbuzonas/openresty:latest
MAINTAINER Steve Buzonas <steve@fancyguy.com>

RUN rm -rf conf/*
COPY nginx $NGINX_PREFIX/
