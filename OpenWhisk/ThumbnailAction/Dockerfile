#
# Docker image for OpenWhisk ThumbnailAction build container
#
FROM nodejs6action

RUN apt-get update \
 && apt-get install -y \
            python \
            zip \
            build-essential

WORKDIR /root
RUN mkdir /root/server /root/output
COPY server /root/server
WORKDIR /root/server
RUN npm install \
 && zip -r thumbnail-action.zip *
CMD mv thumbnail-action.zip /root/output/
