# gr00tCub Docker Container

## Quick Start

### Pull the container
```bash
docker pull ghcr.io/andrearosasco/gr00tcub:main
```

### Run the container
```bash
docker run -it --gpus all -v $(pwd):/home/gr00t/gr00tCub ghcr.io/andrearosasco/gr00tcub:main
```

This command:
- Runs the container interactively (`-it`)
- Enables GPU access (`--gpus all`)
- Mounts the current project directory to `/home/gr00t/gr00tCub` inside the container
- Starts with the `gr00t` conda environment activated

The container includes:
- NVIDIA CUDA 12.4.1 with cuDNN
- Python 3.10 in a conda environment named `gr00t`
- Isaac-GR00T framework pre-installed
- PyTorch 2.5.1 with CUDA support
