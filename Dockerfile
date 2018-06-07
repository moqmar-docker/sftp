FROM alpine

RUN apk add --no-cache openssh-server jq python2 py2-yaml bash
ADD https://github.com/ohjames/smell-baron/releases/download/v0.4.2/smell-baron.musl /bin/smell-baron
ADD setup.sh /setup.sh
ADD sshd_config /etc/ssh/sshd_config

CMD ["/setup.sh"]
