# ---- BUILD STAGE ----
# This stage installs all dependencies and builds the environment.
FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04 AS build

# Arguments for user creation
ARG USER=gr00t

# Environment variables
ENV PYTHONDONTWRITEBYTECODE=true
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/home/${USER}/miniforge/bin:${PATH}"

# Install all build-time and runtime system dependencies
RUN apt-get update && \
    apt-get install --no-install-recommends -y \
    sudo git git-lfs wget bzip2 \
    tzdata netcat dnsutils libgl1-mesa-glx libvulkan-dev \
    zip unzip curl build-essential cmake \
    vim less htop ca-certificates tmux ffmpeg \
    libglib2.0-0 libsm6 libxext6 libxrender-dev && \
    rm -rf /var/lib/apt/lists/*

# Create non-root user
# Note: We don't set a password as it's not needed for this build process.
RUN addgroup ${USER} && \
    useradd -ms /bin/bash ${USER} -g ${USER} && \
    usermod -a -G sudo ${USER} && \
    echo "${USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Switch to the non-root user
USER ${USER}
WORKDIR /home/${USER}

# Install Miniforge and initialize it for bash
# This modifies the .bashrc file, which we will copy to the final stage
ARG CONDA_SCRIPT=Miniforge3-Linux-x86_64.sh
ARG CONDA_LINK=https://github.com/conda-forge/miniforge/releases/latest/download/${CONDA_SCRIPT}
RUN wget --quiet ${CONDA_LINK} -O /tmp/${CONDA_SCRIPT} && \
    bash /tmp/${CONDA_SCRIPT} -b -p /home/${USER}/miniforge && \
    rm /tmp/${CONDA_SCRIPT} && \
    /home/${USER}/miniforge/bin/conda init bash

# Create the conda environment and set it to auto-activate in .bashrc
RUN conda create -n gr00t python=3.10 -y && \
    echo "conda activate gr00t" >> /home/${USER}/.bashrc

# Clone the repository
RUN git clone https://github.com/NVIDIA/Isaac-GR00T.git
WORKDIR /home/${USER}/Isaac-GR00T

# Install all python packages using 'conda run' to avoid activation issues in RUN
# This also combines all installations into a single layer to optimize size
RUN conda run -n gr00t pip install --upgrade pip setuptools && \
    conda run -n gr00t pip install gpustat wandb==0.19.0 && \
    conda run -n gr00t pip install -e .[base] && \
    conda run -n gr00t pip uninstall -y transformer-engine && \
    conda run -n gr00t pip install flash-attn==2.7.1.post4 -U --force-reinstall && \
    (conda run -n gr00t pip uninstall -y opencv-python opencv-python-headless || true) && \
    conda run -n gr00t pip install opencv-python==4.8.0.74 && \
    conda run -n gr00t pip install --force-reinstall torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1 numpy==1.26.4 && \
    conda run -n gr00t pip install accelerate>=0.26.0 && \
    conda run -n gr00t pip install -e . --no-deps && \
    conda clean -afy && \
    pip cache purge

# ---- FINAL STAGE ----
# This stage creates the final, smaller image with only runtime dependencies.
FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04

ARG USER=gr00t

# Set environment variables for the final image
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/home/${USER}/miniforge/bin:${PATH}"

# Install only essential RUNTIME system dependencies to keep the image small
RUN apt-get update && \
    apt-get install --no-install-recommends -y \
    sudo git-lfs wget libgl1-mesa-glx \
    libvulkan-dev libglib2.0-0 libsm6 \
    libxext6 libxrender-dev ffmpeg && \
    rm -rf /var/lib/apt/lists/*

# Create the non-root user for the final image
RUN addgroup ${USER} && \
    useradd -ms /bin/bash -g ${USER} ${USER} && \
    usermod -a -G sudo ${USER} && \
    echo "${USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Copy the pre-built conda environment from the 'build' stage
COPY --from=build /home/${USER}/miniforge /home/${USER}/miniforge

# Copy the application code
COPY --from=build /home/${USER}/Isaac-GR00T /home/${USER}/Isaac-GR00T

# Copy the configured .bashrc from the build stage. This is key for auto-activation.
COPY --from=build /home/${USER}/.bashrc /home/${USER}/.bashrc

# Ensure all files in the user's home directory are owned by the user
USER root
RUN chown -R ${USER}:${USER} /home/${USER}

# Switch to the final user
USER ${USER}
WORKDIR /home/${USER}/Isaac-GR00T

# This is the command that restores the original behavior.
# It starts a bash shell, sources the configured .bashrc to initialize and
# activate the conda environment, and then leaves you in an interactive shell.
CMD ["/bin/bash", "-c", "source /home/gr00t/.bashrc && exec /bin/bash"]
