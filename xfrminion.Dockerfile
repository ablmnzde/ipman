ARG IPROUTE2_IMAGE=ablmnzde/ipman-iproute2:0.1.19-abl2
FROM ${IPROUTE2_IMAGE}
COPY xfrminion /usr/local/bin/xfrminion
ENTRYPOINT ["/usr/local/bin/xfrminion"]
