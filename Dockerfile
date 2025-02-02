FROM registry.redhat.io/ubi9-init:9.5-1736424979

ENV RUNIT='MotionPro_Linux_RedHat_x64_build-8383-30.sh'

COPY entrypoint.sh /
COPY $RUNIT /

RUN dnf install -y iproute openssh-clients && \
    chmod +x $RUNIT && \
    ./$RUNIT && \
    rm $RUNIT

ENTRYPOINT [ "/entrypoint.sh" ]

CMD [ "--help" ]
