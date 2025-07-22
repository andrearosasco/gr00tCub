# Base image with CUDA 12.4.1 and cuDNN on Ubuntu 22.04, as per GR00T prerequisites
FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04

# Arguments for user creation and Conda installation
ARG USER=gr00t
ARG PASSWORD=gr00t
ARG CONDA_SCRIPT=Miniforge3-Linux-x86_64.sh
ARG CONDA_LINK=https://github.com/conda-forge/miniforge/releases/latest/download/${CONDA_SCRIPT}

# Environment variables to prevent interactive prompts and bytecode generation
ENV PYTHONDONTWRITEBYTECODE=true
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies and create a non-root user with sudo access
RUN apt-get update && \
    apt-get install --no-install-recommends -y -qq sudo git wget bzip2 ffmpeg libsm6 libxext6 && \
    rm -rf /var/lib/apt/lists/*

# Create user, set password, and grant passwordless sudo permissions temporarily
RUN addgroup ${USER} && \
    useradd -ms /bin/bash ${USER} -g ${USER} && \
    echo "${USER}:${PASSWORD}" | chpasswd && \
    usermod -a -G sudo ${USER} && \
    sed -i.bak -e 's/%sudo\s\+ALL=(ALL\(:ALL\)\?)\s\+ALL/%sudo ALL=NOPASSWD:ALL/g' /etc/sudoers

# Switch to the non-root user
USER ${USER}
WORKDIR /home/${USER}

# Install Miniforge
RUN wget --quiet ${CONDA_LINK} -O /tmp/${CONDA_SCRIPT} && \
    bash /tmp/${CONDA_SCRIPT} -b -p /home/${USER}/miniforge && \
    rm /tmp/${CONDA_SCRIPT} && \
    /home/${USER}/miniforge/bin/conda init bash && \
    /home/${USER}/miniforge/bin/conda clean -afy

# Add conda to the PATH for subsequent RUN commands
ENV PATH="/home/${USER}/miniforge/bin:${PATH}"

# Create the conda environment for GR00T
RUN conda create -n gr00t python=3.10 -y

# Clone the repository and set it as the working directory
RUN git clone https://github.com/NVIDIA/Isaac-GR00T.git
WORKDIR /home/${USER}/Isaac-GR00T

# Activate the conda environment and install the Python dependencies as per the guide
# Using 'conda run' to execute commands within the specified environment
RUN echo "conda activate gr00t" >> /home/${USER}/.bashrc && \
    conda run -n gr00t pip install --upgrade setuptools && \
    conda run -n gr00t pip install nvidia-tensorrt --extra-index-url https://pypi.ngc.nvidia.com && \
    conda run -n gr00t pip install -e .[base] && \
    conda run -n gr00t pip install --no-build-isolation flash-attn==2.7.1.post4

# Revert sudoers file to its original state for security
USER root
RUN mv /etc/sudoers.bak /etc/sudoers

# Switch back to the non-root user
USER ${USER}
WORKDIR /home/${USER}/Isaac-GR00T

# Set the default command to start a bash session with the conda environment activated
CMD ["/bin/bash", "-c", "source /home/gr00t/.bashrc; exec /bin/bash"]
