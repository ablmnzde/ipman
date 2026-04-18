ARG SWANCTL_IMAGE=ablmnzde/ipman-swanctl:0.1.19-abl1
FROM ${SWANCTL_IMAGE}
COPY restctl /usr/local/bin/restctl
ENTRYPOINT ["/usr/local/bin/restctl"]
