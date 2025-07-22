# Use the official NVIDIA CUDA image as the base
FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04

# Arguments for user creation
ARG USER=gr00t
ARG PASSWORD=gr00t

# Environment variables to prevent interactive prompts and bytecode generation
ENV PYTHONDONTWRITEBYTECODE=true
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies, merging ours with the official list
RUN apt-get update && \
    apt-get install --no-install-recommends -y \
    # For user setup and conda
    sudo git wget bzip2 \
    # Official Repo Dependencies
    tzdata netcat dnsutils libgl1-mesa-glx libvulkan-dev \
    zip unzip curl git-lfs build-essential cmake \
    vim less htop ca-certificates tmux ffmpeg \
    libglib2.0-0 libsm6 libxext6 libxrender-dev && \
    rm -rf /var/lib/apt/lists/*

# Create non-root user with passwordless sudo (as before)
RUN addgroup ${USER} && \
    useradd -ms /bin/bash ${USER} -g ${USER} && \
    echo "${USER}:${PASSWORD}" | chpasswd && \
    usermod -a -G sudo ${USER} && \
    sed -i.bak -e 's/%sudo\s\+ALL=(ALL\(:ALL\)\?)\s\+ALL/%sudo ALL=NOPASSWD:ALL/g' /etc/sudoers

# Switch to the non-root user
USER ${USER}
WORKDIR /home/${USER}

# Install Miniforge (as before)
ARG CONDA_SCRIPT=Miniforge3-Linux-x86_64.sh
ARG CONDA_LINK=https://github.com/conda-forge/miniforge/releases/latest/download/${CONDA_SCRIPT}
RUN wget --quiet ${CONDA_LINK} -O /tmp/${CONDA_SCRIPT} && \
    bash /tmp/${CONDA_SCRIPT} -b -p /home/${USER}/miniforge && \
    rm /tmp/${CONDA_SCRIPT} && \
    /home/${USER}/miniforge/bin/conda init bash && \
    /home/${USER}/miniforge/bin/conda clean -afy

# Add conda to the PATH for all subsequent commands
ENV PATH="/home/${USER}/miniforge/bin:${PATH}"

# --- CACHING AND INSTALLATION LOGIC ---

# Create the conda environment first
RUN conda create -n gr00t python=3.10 -y && \
    echo "conda activate gr00t" >> /home/${USER}/.bashrc

# Set working directory for the project
WORKDIR /home/${USER}/Isaac-GR00T

# Copy only the files required for dependency installation first.
# This layer will be cached and reused as long as these files don't change.
COPY --chown=gr00t:gr00t setup.py pyproject.toml README.md ./

# Run the full, official installation and conflict resolution sequence.
# This is the most important step and is now aligned with the official Dockerfile.
RUN conda run -n gr00t /bin/bash -c " \
    set -ex && \
    pip install --upgrade pip setuptools && \
    pip install gpustat wandb==0.19.0 && \
    # 1. Initial install, which is known to create conflicts
    pip install -e .[base] && \
    # 2. Fix known conflict by removing transformer-engine
    pip uninstall -y transformer-engine && \
    # 3. Reinstall flash-attn correctly
    pip install flash-attn==2.7.1.post4 -U --force-reinstall && \
    # 4. Fix OpenCV version
    pip uninstall -y opencv-python opencv-python-headless || true && \
    pip install opencv-python==4.8.0.74 && \
    # 5. Force-reinstall torch and numpy to fix versions clobbered by other packages
    pip install --force-reinstall torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1 numpy==1.26.4 && \
    # 6. Install accelerate separately
    pip install accelerate>=0.26.0 \
    "

# Now, copy the rest of the application code. If you only change a script,
# the build will use the cache for all previous layers and start from here.
COPY --chown=gr00t:gr00t . .

# Final step from the official file: install in editable mode without reinstalling dependencies.
# This ensures the `gr00t` package is correctly recognized by Python.
RUN conda run -n gr00t pip install -e . --no-deps

# Revert sudoers file to its original state for security
USER root
RUN mv /etc/sudoers.bak /etc/sudoers

# Switch back to the non-root user and set the default command
USER ${USER}
WORKDIR /home/${USER}/Isaac-GR00T
CMD ["/bin/bash", "-c", "source /home/gr00t/.bashrc; exec /bin/bash"]
