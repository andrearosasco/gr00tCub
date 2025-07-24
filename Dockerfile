# ---- BUILD STAGE ----
# Use the official NVIDIA CUDA image as the base for the build environment
FROM pytorch/pytorch:2.6.0-cuda12.4-cudnn9-devel AS build

# Arguments for user creation
ARG USER=gr00t
ARG PASSWORD=gr00t

# Environment variables
ENV PYTHONDONTWRITEBYTECODE=true
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies required for building
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
    echo "${USER}:${PASSWORD}" | chpasswd && \
    usermod -a -G sudo ${USER} && \
    sed -i.bak -e 's/%sudo\s\+ALL=(ALL\(:ALL\)\?)\s\+ALL/%sudo ALL=NOPASSWD:ALL/g' /etc/sudoers

# Switch to the non-root user
USER ${USER}
WORKDIR /home/${USER}

# Install Miniforge
ARG CONDA_SCRIPT=Miniforge3-Linux-x86_64.sh
ARG CONDA_LINK=https://github.com/conda-forge/miniforge/releases/latest/download/${CONDA_SCRIPT}
RUN wget --quiet ${CONDA_LINK} -O /tmp/${CONDA_SCRIPT} && \
    bash /tmp/${CONDA_SCRIPT} -b -p /home/${USER}/miniforge && \
    rm /tmp/${CONDA_SCRIPT} && \
    /home/${USER}/miniforge/bin/conda init bash && \
    /home/${USER}/miniforge/bin/conda clean -afy

# Add conda to the PATH
ENV PATH="/home/${USER}/miniforge/bin:${PATH}"

# Create and activate the conda environment, then install dependencies
RUN conda create -n gr00t python=3.10 -y && \
    echo "conda activate gr00t" >> /home/${USER}/.bashrc

# Clone the repository
RUN git clone https://github.com/NVIDIA/Isaac-GR00T.git && \
    git clone https://github.com/ARISE-Initiative/robosuite.git && \
    git clone https://github.com/robocasa/robocasa-gr1-tabletop-tasks.git

# Install Python packages and clean cache in a single layer
RUN conda run -n gr00t pip install --upgrade pip setuptools && \
    conda run -n gr00t pip install gpustat wandb==0.19.0 && \
    conda run -n gr00t pip install -e Isaac-GR00T[base] && \
    conda run -n gr00t pip uninstall -y transformer-engine && \
    conda run -n gr00t pip install flash-attn==2.7.1.post4 -U --force-reinstall && \
    (conda run -n gr00t pip uninstall -y opencv-python opencv-python-headless || true) && \
    conda run -n gr00t pip install opencv-python==4.8.0.74 && \
    conda run -n gr00t pip install --force-reinstall torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1 numpy==1.26.4 && \
    conda run -n gr00t pip install "accelerate>=0.26.0" && \
    conda run -n gr00t pip install -e Isaac-GR00T --no-deps && \
    conda run -n gr00t pip install -e robosuite && \
    conda run -n gr00t pip install -e robocasa-gr1-tabletop-tasks && cd robocasa-gr1-tabletop-tasks && conda run -n gr00t python robocasa/scripts/download_tabletop_assets.py -y && \
    conda clean -afy

# --- FINAL STAGE ---
# Use a smaller base image for the final stage
FROM pytorch/pytorch:2.6.0-cuda12.4-cudnn9-devel

# Arguments for user creation (must be redeclared in new stage)
ARG USER=gr00t
ARG PASSWORD=gr00t

# Environment variables
ENV PYTHONDONTWRITEBYTECODE=true
ENV DEBIAN_FRONTEND=noninteractive
ENV NO_ALBUMENTATIONS_UPDATE=1

# Install only necessary runtime system dependencies
RUN apt-get update && \
    apt-get install --no-install-recommends -y \
    sudo git-lfs wget \
    libgl1-mesa-glx libvulkan-dev \
    libglib2.0-0 libsm6 libxext6 libxrender-dev ffmpeg && \
    rm -rf /var/lib/apt/lists/*

# Create the non-root user, set their password, and add to sudo group.
# By NOT adding a NOPASSWD rule, the user will be prompted for their password.
RUN addgroup ${USER} && \
    useradd -ms /bin/bash -g ${USER} ${USER} && \
    echo "${USER}:${PASSWORD}" | chpasswd && \
    usermod -a -G sudo ${USER}

USER ${USER}
# Copy the conda environment from the build stage
COPY --chown=gr00t --from=build /home/${USER}/miniforge /home/${USER}/miniforge
COPY --chown=gr00t --from=build /home/${USER}/Isaac-GR00T /home/${USER}/Isaac-GR00T
COPY --chown=gr00t --from=build /home/${USER}/robosuite /home/${USER}/robosuite
COPY --chown=gr00t --from=build /home/${USER}/robocasa-gr1-tabletop-tasks /home/${USER}/robocasa-gr1-tabletop-tasks
COPY --chown=gr00t --from=build /home/${USER}/.bashrc /home/${USER}/.bashrc

# Default command
CMD ["bash"]
