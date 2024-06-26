FROM codercom/enterprise-base:ubuntu

ARG USER=coder
# Run everything as root
USER root

# Install whichever Node version is LTS 20
RUN curl -sL https://deb.nodesource.com/setup_18.x | bash -
RUN DEBIAN_FRONTEND="noninteractive" apt-get update -y && \
    apt-get install -y nodejs

# npm global modules in local users home
ENV NPM_CONFIG_PREFIX=/home/${USER}/.npm-global
ENV PATH=$PATH:/home/${USER}/.npm-global/bin

# Github CLI
RUN mkdir -p -m 755 /etc/apt/keyrings && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && sudo apt update \
    && sudo apt install gh -y

RUN apt install jq -y

RUN curl -sS https://starship.rs/install.sh | sh -s -- -y

RUN useradd --groups sudo,docker --create-home --shell /bin/bash ${USER} \
	&& echo "${USER} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/${USER} \
	&& chmod 0440 /etc/sudoers.d/${USER}

RUN echo 'eval "$(starship init bash)"' >> /home/${USER}/.bashrc

# install temporal
RUN curl -sSf https://temporal.download/cli.sh | sh -s -- --dir /home/${USER}/.temporalio

# add temporal to path
ENV PATH="$PATH:/home/${USER}/.temporalio/bin"

USER ${USER}
WORKDIR /home/${USER}