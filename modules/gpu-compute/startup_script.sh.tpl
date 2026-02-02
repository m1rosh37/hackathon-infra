#!/bin/bash

LOG="/var/log/hackathon-startup.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== Hackathon startup script started ==="

# CONSTANTS
CONDA_DIR=/opt/conda
CONDA_BIN=$CONDA_DIR/bin/conda
ENV_NAME=hackathon
GCS_MOUNT=/home/storage
BUCKET_NAME=${bucket_name}
REBOOT_MARKER=/var/lib/hackathon-gpu-installed

# -------------------------------------------------------------------
# BASE SYSTEM PACKAGES
# -------------------------------------------------------------------
apt-get update
apt-get install -y \
  git \
  curl \
  ca-certificates \
  gnupg \
  lsb-release \
  python3 \
  python3-pip

# -------------------------------------------------------------------
# GCSFUSE (official repo)
# -------------------------------------------------------------------
if ! command -v gcsfuse >/dev/null 2>&1; then
  echo "Installing gcsfuse..."
  export GCSFUSE_REPO=gcsfuse-$(lsb_release -c -s)
  echo "deb https://packages.cloud.google.com/apt $GCSFUSE_REPO main" \
    > /etc/apt/sources.list.d/gcsfuse.list
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
  apt-get update
  apt-get install -y gcsfuse
fi

# -------------------------------------------------------------------
# NVIDIA GPU DRIVER (official GCP installer)
# -------------------------------------------------------------------
if ! command -v nvidia-smi >/dev/null 2>&1; then
  if [ ! -f "$REBOOT_MARKER" ]; then
    echo "Installing NVIDIA driver via GCP installer..."
    curl -fsSL \
      https://raw.githubusercontent.com/GoogleCloudPlatform/compute-gpu-installation/main/linux/install_gpu_driver.py \
      -o /tmp/install_gpu_driver.py
    python3 /tmp/install_gpu_driver.py || true
    touch "$REBOOT_MARKER"
    echo "Rebooting after GPU driver install..."
    reboot
    exit 0
  fi
fi

echo "GPU driver phase complete"

# -------------------------------------------------------------------
# ANACONDA
# -------------------------------------------------------------------
if [ ! -x "$CONDA_BIN" ]; then
  echo "Installing Anaconda..."
  curl -fsSL \
    https://repo.anaconda.com/archive/Anaconda3-2023.09-0-Linux-x86_64.sh \
    -o /tmp/anaconda.sh
  bash /tmp/anaconda.sh -b -p $CONDA_DIR
  rm /tmp/anaconda.sh
  ln -s $CONDA_BIN /usr/local/bin/conda
fi

# Make conda available system-wide
if ! grep -q conda.sh /etc/profile; then
  echo ". $CONDA_DIR/etc/profile.d/conda.sh" >> /etc/profile
fi

source $CONDA_DIR/etc/profile.d/conda.sh

# -------------------------------------------------------------------
# CONDA ENVIRONMENT
# -------------------------------------------------------------------
if ! conda env list | grep -q "^$ENV_NAME"; then
  echo "Creating conda environment: $ENV_NAME"

  cat << 'EOF' > /tmp/hackathon-env.yml
name: hackathon
channels:
  - conda-forge
  - pytorch
  - defaults
dependencies:
  - python=3.10
  - numpy>=1.24.0
  - pandas
  - scipy>=1.10.0
  - scikit-learn>=1.3.0
  - matplotlib
  - seaborn
  - tqdm
  - lxml
  - pyyaml
  - pytorch>=2.0.0
  - ipython
  - jupyter
  - transformers
  - tokenizers
  - sentencepiece
  - accelerate
  - datasets
  - wandb
  - pip
  - pip:
      - hf_xet
      - huggingface_hub
      - eval4ner
      - langchain
      - langchain_community
      - langchain-huggingface
      - langchain-openai
      - langchain-google-genai
      - langchain-anthropic
      - langchain-together
      - langchain-cohere
      - google-genai
      - together
EOF

  conda env create -f /tmp/hackathon-env.yml
fi

# -------------------------------------------------------------------
# GCS MOUNT (persistent)
# -------------------------------------------------------------------
mkdir -p $GCS_MOUNT

if ! grep -q "$GCS_MOUNT" /etc/fstab; then
  echo "Configuring persistent GCS mount..."
  echo "$BUCKET_NAME $GCS_MOUNT gcsfuse rw,allow_other,implicit_dirs,_netdev 0 0" >> /etc/fstab
fi

mount -a || true
chown -R 1000:1000 $GCS_MOUNT || true

# -------------------------------------------------------------------
# VALIDATION
# -------------------------------------------------------------------
echo "Final validation:"
nvidia-smi || echo "WARNING: nvidia-smi not available"

source $CONDA_DIR/etc/profile.d/conda.sh
conda activate $ENV_NAME || true

python - <<EOF
import torch
print("CUDA available:", torch.cuda.is_available())
EOF

echo "=== Hackathon startup script completed successfully ==="
