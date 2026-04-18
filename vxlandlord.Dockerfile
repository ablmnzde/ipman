ARG IPROUTE2_IMAGE=ablmnzde/ipman-iproute2:0.1.19-abl2
FROM ${IPROUTE2_IMAGE}
COPY vxlandlord /usr/local/bin/vxlandlord
ENTRYPOINT ["/usr/local/bin/vxlandlord"]
