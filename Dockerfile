# syntax=docker/dockerfile:1.3

# testing with https://github.com/moby/buildkit/issues/1673#issuecomment-698361687
# docker rm -f buildx_buildkit_localbuild0 ; docker buildx create --use --name localbuild  && docker buildx inspect localbuild --bootstrap && docker rm -f buildx_buildkit_localbuild0 && docker run --privileged -d --name=buildx_buildkit_localbuild0 -v=/dev/shm/buildkit:/var/lib/buildkit moby/buildkit:buildx-stable-1
## docker buildx create --use --name localbuild
## docker buildx inspect localbuild --bootstrap
# recreate buildkit with host path
## docker rm -f buildx_buildkit_localbuild0
## docker run --privileged -d --name=buildx_buildkit_localbuild0 -v=/tmp/buildkit:/var/lib/buildkit moby/buildkit:buildx-stable-1


# build it with: docker build . -t vodafone-station-exporter
# run it with: docker run --rm -d --restart unless-stopped -p 9420:9420 -e VF_STATION_PASS=<password> -e VF_STATION_URL=http://192.168.0.1 vodafone-station-exporter
# or with: docker run --rm -it -p 9420:9420 --env-file .ENV-PW vodafone-station-exporter

# echo loglevel=debug >> .ENV-PW ; echo station_password=XXXX >> .ENV-PW ;
# docker buildx build . -t vodafone-station-exporter-dev:latest && docker run --rm -it -p 9420:942--env-file .ENV-PW vodafone-station-exporter-dev:latest
# docker buildx build . -t vodafone-station-exporter-dev:test && docker run --rm -it -p 9420:9420 vodafone-station-exporter-dev:test
# docker buildx build --progress plain . -t vodafone-station-exporter-dev:test && docker run --rm -it --env-file .ENV-PW --env DEBUG=foo -p 9420:9420 vodafone-station-exporter-dev:test


# https://github.com/tonistiigi/xx
FROM --platform=$BUILDPLATFORM tonistiigi/xx AS xx

#FROM golang:1.18-alpine as builder
FROM --platform=$BUILDPLATFORM golang:1.18-alpine as builder
# copy xx scripts to your build stage
COPY --from=xx / /
ARG BUILDPLATFORM TARGETOS TARGETARCH TARGETPLATFORM
#ARG TARGETARCH
#ARG TARGETPLATFORM
#ARG BUILDPLATFORM
# you can now call xx-* commands
RUN xx-info env
RUN echo "I am running on $BUILDPLATFORM, building for $TARGETPLATFORM"
# --platform=$BUILDPLATFORM see https://www.docker.com/blog/faster-multi-platform-builds-dockerfile-cross-compilation-guide/
ADD . /go/vodafone-station-exporter
WORKDIR /go/vodafone-station-exporter

RUN apk add file #


# Building Go can be achieved with the xx-go wrapper that automatically sets up values for GOOS, GOARCH, GOARM etc. It also sets up pkg-config and C compiler if building with CGo. Note that by default, CGo is enabled in Go when compiling for native architecture and disabled when cross-compiling. This can easily produce unexpected results; therefore, you should always define either CGO_ENABLED=1 or CGO_ENABLED=0 depending on if you expect your compilation to use CGo or not. https://github.com/tonistiigi/xx
#ENV CGO_ENABLED=1
ENV CGO_ENABLED=0

# see https://www.docker.com/blog/faster-multi-platform-builds-dockerfile-cross-compilation-guide/
# RUN --mount=target=. \
#    --mount=type=cache,target=/root/.cache/go-build \
#    --mount=type=cache,target=/go/pkg \
#    GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /out/myapp .

# -ldflags="-s -w" for Shrinking Go executables, https://itnext.io/shrinking-go-executable-9e9c17b47a41
### RUN --mount=type=cache,id=gomod,sharing=locked,mode=0775,target=/go/pkg/mod \
###     --mount=type=cache,id=gobuild,sharing=locked,mode=0775,target=/root/.cache/go-build \
#RUN
RUN --mount=type=cache,id=gomod,sharing=locked,mode=0775,target=/go/pkg/mod \
    --mount=type=cache,id=gobuild,sharing=locked,mode=0775,target=/root/.cache/go-build \
    set -x && \
    go build -v "fmt" && \
    go env GOCACHE && \
    du -hd0 $(go env GOCACHE) && \
    go env GOMODCACHE && \
    du -hd0 $(go env GOMODCACHE) && \
    GOOS=$TARGETOS GOARCH=$TARGETARCH go mod download && \
    du -hd0 $(go env GOCACHE) && \
    du -hd0 $(go env GOMODCACHE)
### RUN --mount=type=cache,id=gomod,sharing=locked,mode=0775,target=/go/pkg/mod \
###     --mount=type=cache,id=gobuild,sharing=locked,mode=0775,target=/root/.cache/go-build \
RUN    set -x && \
    go build -v "fmt" && \
    go env GOCACHE && \
    du -hd0 $(go env GOCACHE) && \
    go env GOMODCACHE && \
    du -hd0 $(go env GOMODCACHE) && \
    GOOS=$TARGETOS GOARCH=$TARGETARCH go build -v -ldflags="-extldflags=-static -s -w -X main.version={{.Version}} -X main.commit={{.Commit}} -X main.date={{.Date}}" && \
    du -hd0 $(go env GOCACHE) && \
    du -hd0 $(go env GOMODCACHE)
    #GOOS=$TARGETOS GOARCH=$TARGETARCH go build -v -ldflags="-extldflags=-static -s -w -X main.version={{.Version}} -X main.commit={{.Commit}} -X main.date={{.Date}}" && \

RUN    XX_DEBUG_VERIFY=foo xx-verify vodafone-station-exporter
## # GODEBUG=gocachehash=1 go build -v -ldflags="-s -w" && \
## # go build -ldflags="-s -w"
## # GODEBUG=gocachehash=1 go build -v "fmt"
## # xx-verify --static vodafone-station-exporter

FROM alpine:3.17
WORKDIR /app
#RUN apk --no-cache add file ldd
RUN apk add file scanelf elfutils patchelf
COPY --from=builder /go/vodafone-station-exporter/vodafone-station-exporter .

ENV logLevel=${logLevel:-debug} \
	vodafoneStationPassword={vodafoneStationPassword:-FIXME} \
	vodafoneStationUrl=${vodafoneStationUrl:-http://192.168.0.1} \
	listenAddress=${listenAddress:-[::]:9420} \
	metricsPath=${metricsPath:-/metrics}

#CMD "/app/vodafone-station-exporter -log.level ${loglevel} -vodafone.station-password ${station_password} -vodafone.station-url ${station_url} -web.listen-address ${listen_address} -web.telemetry-path ${telemetry_path}"
#CMD ["/app/vodafone-station-exporter","-log.level=${loglevel}","-vodafone.station-password=${station_password}","-vodafone.station-url=${station_url}","-web.listen-address=${listen_address}","-web.telemetry-path=${telemetry_path}"]
#CMD ["/app/vodafone-station-exporter"]
#CMD /bin/sh -vx -c 'env && set && /app/vodafone-station-exporter -log.level=$logLevel -vodafone.station-password=$vodafoneStationPassword -vodafone.station-url=$vodafoneStationUrl -web.listen-address=$listenAddress -web.telemetry-path=$metricsPath '
#CMD /bin/sh -vx -c '/app/vodafone-station-exporter -log.level=$logLevel -vodafone.station-password=$vodafoneStationPassword -vodafone.station-url=$vodafoneStationUrl -web.listen-address=$listenAddress -web.telemetry-path=$metricsPath '

COPY --chmod=755 vodafone-station-exporter-entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 9420
ENV PATH="$PATH:/apt/" 
USER nobody
ENTRYPOINT ["entrypoint.sh"]
CMD ["vodafone-station-exporter-entrypoint"]


