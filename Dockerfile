# ---- BUILD STAGE ----
# Use the full development image to build the environment
FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04 AS build

# Arguments for user creation
ARG USER=gr00t

# Environment variables
ENV PYTHONDONTWRITEBYTECODE=true
ENV DEBIAN_FRONTEND=noninteractive

# Install all build-time system dependencies in a single layer
RUN apt-get update && \
    apt-get install --no-install-recommends -y \
    sudo git git-lfs wget bzip2 \
    tzdata netcat dnsutils libgl1-mesa-glx libvulkan-dev \
    zip unzip curl build-essential cmake \
    vim less htop ca-certificates tmux ffmpeg \
    libglib2.0-0 libsm6 libxext6 libxrender-dev && \
    rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN addgroup ${USER} && \
    useradd -ms /bin/bash ${USER} -g ${USER} && \
    echo "${USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USER} && \
    chmod 0440 /etc/sudoers.d/${USER}

# Switch to the non-root user
USER ${USER}
WORKDIR /home/${USER}

# Install Miniforge
ARG CONDA_SCRIPT=Miniforge3-Linux-x86_64.sh
ARG CONDA_LINK=https://github.com/conda-forge/miniforge/releases/latest/download/${CONDA_SCRIPT}
RUN wget --quiet ${CONDA_LINK} -O /tmp/${CONDA_SCRIPT} && \
    bash /tmp/${CONDA_SCRIPT} -b -p /home/${USER}/miniforge && \
    rm /tmp/${CONDA_SCRIPT}

# Add conda to the PATH
ENV PATH="/home/${USER}/miniforge/bin:${PATH}"

# Initialize conda for the shell
RUN /home/${USER}/miniforge/bin/conda init bash

# Create conda environment and set it to activate on shell startup
RUN conda create -n gr00t python=3.10 -y && \
    echo "conda activate gr00t" >> /home/${USER}/.bashrc

# Clone the repository
RUN git clone https://github.com/NVIDIA/Isaac-GR00T.git

# Set the working directory
WORKDIR /home/${USER}/Isaac-GR00T

# Install all python packages and clear caches in a single RUN command
# This creates a more efficient layer
RUN . /home/${USER}/.bashrc && \
    conda activate gr00t && \
    pip install --upgrade pip setuptools && \
    pip install gpustat wandb==0.19.0 && \
    pip install -e .[base] && \
    pip uninstall -y transformer-engine && \
    pip install flash-attn==2.7.1.post4 -U --force-reinstall && \
    (pip uninstall -y opencv-python opencv-python-headless || true) && \
    pip install opencv-python==4.8.0.74 && \
    pip install --force-reinstall torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1 numpy==1.26.4 && \
    pip install accelerate>=0.26.0 && \
    pip install -e . --no-deps && \
    conda clean -afy && \
    pip cache purge

# ---- FINAL STAGE ----
# Use the smaller runtime image for the final product
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

# Arguments for user creation
ARG USER=gr00t

# Environment variables
ENV PYTHONDONTWRITEBYTECODE=true
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/home/${USER}/miniforge/bin:${PATH}"
ENV NO_ALBUMENTATIONS_UPDATE=1

# Install only necessary runtime system dependencies
RUN apt-get update && \
    apt-get install --no-install-recommends -y \
    sudo git-lfs \
    libgl1-mesa-glx libvulkan-dev \
    libglib2.0-0 libsm6 libxext6 libxrender-dev ffmpeg && \
    rm -rf /var/lib/apt/lists/*

# Create the same non-root user
RUN addgroup ${USER} && \
    useradd -ms /bin/bash -g ${USER} ${USER} && \
    echo "${USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USER} && \
    chmod 0440 /etc/sudoers.d/${USER}

# Copy the application, conda environment, and shell configuration from the build stage
# Use --chown to set correct permissions without an extra layer
COPY --from=build --chown=${USER}:${USER} /home/${USER}/miniforge /home/${USER}/miniforge
COPY --from=build --chown=${USER}:${USER} /home/${USER}/Isaac-GR00T /home/${USER}/Isaac-GR00T
COPY --from=build --chown=${USER}:${USER} /home/${USER}/.bashrc /home/${USER}/.bashrc

# Switch to the non-root user and set the working directory
USER ${USER}
WORKDIR /home/${USER}/Isaac-GR00T

# The CMD now executes an interactive bash shell.
# Because we copied the configured .bashrc, it will be sourced automatically,
# activating the conda environment.
CMD ["/bin/bash"]
