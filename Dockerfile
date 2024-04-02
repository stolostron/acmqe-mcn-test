FROM quay.io/fedora/fedora:39

ARG SUBM=submariner
ARG NODE_VERSION=20
ARG CHROME=https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm
ARG OCP_CLI=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz
ARG YQ=https://github.com/mikefarah/yq/releases/download/v4.16.2/yq_linux_amd64
ARG AWS_CLI=https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
ARG ROSA_CLI=https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/rosa/latest/rosa-linux.tar.gz

# The user ID set to match the one used in Jenkins and avoid permissions issues during job execution
RUN mkdir -p /"$SUBM" \
    && adduser "$SUBM" \
    && chown -R "$SUBM" /"$SUBM"

RUN dnf install --nodocs -y \
    wget \
    curl \
    gzip \
    unzip \
    xz \
    vim \
    git \
    python3 \
    python3-pip \
    jq \
    xorg-x11-server-Xvfb \
    gtk2-devel \
    gtk3-devel \
    libnotify-devel \
    GConf2 \
    nss \
    libXScrnSaver \
    alsa-lib \
    && curl -fsSL https://rpm.nodesource.com/setup_"$NODE_VERSION".x | bash - \
    && dnf install -y nodejs \
    && dnf install -y "$CHROME" \
    && dnf clean all \
    && rm -rf /var/cache/yum \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3 1

RUN wget -qO- "$OCP_CLI" | tar zxv -C /usr/local/bin/ oc kubectl \
    && wget -qO- "$YQ" -O /usr/local/bin/yq && chmod +x /usr/local/bin/yq \
    && wget -qO- "$ROSA_CLI" | tar zxv --no-same-owner -C /usr/local/bin/ rosa \
    && curl "$AWS_CLI" -o aws.zip && unzip aws.zip && ./aws/install && rm -rf aws*

COPY requirements.txt requirements.yml ./

RUN pip install --no-cache-dir -r requirements.txt \
    && mkdir -p /usr/share/ansible/collections \
    && ansible-galaxy collection install --no-cache -r requirements.yml -p /usr/share/ansible/collections

USER "$SUBM"

WORKDIR /"$SUBM"
